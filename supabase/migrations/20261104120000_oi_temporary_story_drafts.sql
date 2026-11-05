begin;

-- Temporary writing access is a server policy, never a synthetic donation approval.
create table benchmark_private.oi_story_creation_settings (
  singleton boolean primary key default true check (singleton),
  unapproved_drafts_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into benchmark_private.oi_story_creation_settings(singleton) values(true);
alter table benchmark_private.oi_story_creation_settings enable row level security;
revoke all on benchmark_private.oi_story_creation_settings from public,anon,authenticated;
alter table public.oi_stories alter column grant_id drop not null;

create function benchmark_private.oi_unapproved_drafts_enabled() returns boolean
language sql stable security definer set search_path='' as $$
  select coalesce((select unapproved_drafts_enabled from benchmark_private.oi_story_creation_settings where singleton),false);
$$;
revoke all on function benchmark_private.oi_unapproved_drafts_enabled() from public,anon;
grant execute on function benchmark_private.oi_unapproved_drafts_enabled() to authenticated;

create function public.oi_set_unapproved_drafts(p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid := benchmark_private.oi_actor();
begin
  if actor is null or not benchmark_private.oi_is_operator() then
    raise exception 'Operator required' using errcode='42501';
  end if;
  if p_enabled is null then raise exception 'Enabled must be boolean' using errcode='22023'; end if;
  update benchmark_private.oi_story_creation_settings
    set unapproved_drafts_enabled=p_enabled,updated_at=now() where singleton;
  insert into benchmark_private.oi_audit(actor_id,action,target_id)
    values(actor,case when p_enabled then 'enable_unapproved_drafts' else 'disable_unapproved_drafts' end,actor);
  return p_enabled;
end; $$;
revoke all on function public.oi_set_unapproved_drafts(boolean) from public,anon;
grant execute on function public.oi_set_unapproved_drafts(boolean) to authenticated;

-- Preserve existing capabilities, including canonical account/merge information.
do $patch$
declare definition text; anchor text := '''coins_enabled'',false,';
begin
  select pg_get_functiondef('public.oi_capabilities()'::regprocedure) into definition;
  if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 then
    raise exception 'Unexpected oi_capabilities definition; review before deployment';
  end if;
  execute replace(definition,anchor,anchor||'''unapproved_drafts_enabled'',benchmark_private.oi_unapproved_drafts_enabled(),');
end; $patch$;

-- Both audited RPC variants are supported; keep deployed campus height/heading handling.
do $patch$
declare definition text; source text;
begin
  select prosrc,pg_get_functiondef(oid) into source,definition from pg_proc
    where oid='benchmark_private.oi_mutate(text,jsonb)'::regprocedure;
  if md5(btrim(source,E' \n\r\t')) not in ('9ee66accdd282841e08ca95afb6dc29d','febcb22fcee3c12fe55efb3eee50b9d1') then
    raise exception 'oi_mutate drift requires review before temporary writing migration';
  end if;
  -- Serialize a mode change with in-flight story writes, and same-ID creation with updates.
  definition:=replace(definition,
    '  if target is null then raise exception ''ID required'' using errcode=''22023''; end if;',
    $new$  if target is null then raise exception 'ID required' using errcode='22023'; end if;
  if action in ('save_story','save_campus_story','attach_media','submit_story','reopen_story','delete_story','review_story') then
    perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('oi_story:'||target::text,0));
  end if;$new$);
  definition:=replace(definition,
    $old$    select * into permission from public.oi_writing_grants
      where id=(payload->>'grant_id')::uuid and user_id=actor and revoked_at is null for update;
    if not found then raise exception 'Writing approval required' using errcode='42501'; end if;$old$,
    $new$    if payload->>'grant_id' is null then
      if not benchmark_private.oi_unapproved_drafts_enabled() then
        raise exception 'Writing approval required; saved drafts and photos are preserved' using errcode='42501';
      end if;
    else
      select * into permission from public.oi_writing_grants
        where id=(payload->>'grant_id')::uuid and user_id=actor and revoked_at is null for update;
      if not found then raise exception 'Writing approval required' using errcode='42501'; end if;
    end if;$new$);
  definition:=replace(definition,'story.user_id<>actor or story.grant_id<>permission.id',
    'story.user_id<>actor or (story.grant_id is not null and story.grant_id is distinct from permission.id)');
  definition:=replace(definition,
    $old$      if (select count(*) from public.oi_stories where grant_id=permission.id)>=permission.story_limit then
        raise exception 'Approved story count exhausted' using errcode='42501';
      end if;
    end if;$old$,
    $new$    end if;
    -- Claiming an approval for an existing temporary draft also consumes its quota.
    if permission.id is not null and story.grant_id is null then
      if (select count(*) from public.oi_stories where grant_id=permission.id)>=permission.story_limit then
        raise exception 'Approved story count exhausted' using errcode='42501';
      end if;
    end if;$new$);
  definition:=replace(definition,'on conflict(id) do update set title=excluded.title',
    'on conflict(id) do update set grant_id=excluded.grant_id,title=excluded.title');
  definition:=replace(definition,
    $old$    if action<>'delete_story' and permission.revoked_at is not null then raise exception 'Writing approval revoked' using errcode='42501'; end if;$old$,
    $new$    if action<>'delete_story' and permission.revoked_at is not null then raise exception 'Writing approval revoked' using errcode='42501'; end if;
    if story.grant_id is null and not benchmark_private.oi_unapproved_drafts_enabled()
      and (action in ('attach_media','submit_story') or (action='review_story' and payload->>'status'='published')) then
      raise exception 'Writing approval required; saved drafts and photos are preserved' using errcode='42501';
    end if;$new$);
  execute definition;
end; $patch$;

-- Do not revoke SELECT or remove files on mode changes. Only new uploads are gated.
create function benchmark_private.oi_can_upload_story_media(story_id_text text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
  return exists(select 1 from public.oi_stories s
    left join public.oi_writing_grants g on g.id=s.grant_id
    where s.id::text=story_id_text and s.user_id=benchmark_private.oi_actor() and s.status='draft'
      and ((s.grant_id is null and benchmark_private.oi_unapproved_drafts_enabled())
        or (g.user_id=s.user_id and g.revoked_at is null)));
end; $$;
revoke all on function benchmark_private.oi_can_upload_story_media(text) from public,anon;
grant execute on function benchmark_private.oi_can_upload_story_media(text) to authenticated;
create policy oi_media_writing_access on storage.objects as restrictive for insert to authenticated
  with check (bucket_id<>'oi-story-media' or benchmark_private.oi_can_upload_story_media((storage.foldername(name))[2]));

notify pgrst,'reload schema';
commit;

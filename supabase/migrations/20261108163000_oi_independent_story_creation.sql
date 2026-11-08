begin;

-- Keep both supported save_story definitions, including the deployed campus variant.
do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure);
  change record;
begin
  for change in
    select * from (values
      ($old$  permission public.oi_writing_grants;
$old$, ''),
      ($old$  capacity integer;
$old$, ''),
      ($old$    if wanted_status='approved' then
      capacity := (payload->>'story_limit')::integer;
      if capacity is null or capacity<1 then raise exception 'Specify approved story count' using errcode='22023'; end if;
      insert into public.oi_writing_grants(evidence_id,user_id,story_limit) values(target,request.user_id,capacity);
    elsif wanted_status='revoked' then
      update public.oi_writing_grants set revoked_at=now() where evidence_id=target;
      update public.oi_stories set status='hidden',revision=revision+1,updated_at=now()
        where grant_id in(select id from public.oi_writing_grants where evidence_id=target) and status<>'deleted';
    end if;$old$,
       $new$    if wanted_status='revoked' then
      update public.oi_writing_grants set revoked_at=now() where evidence_id=target;
    end if;$new$),
      ($old$    if payload->>'grant_id' is null then
      if not benchmark_private.oi_unapproved_drafts_enabled() then
        raise exception 'Writing approval required; saved drafts and photos are preserved' using errcode='42501';
      end if;
    else
      select * into permission from public.oi_writing_grants
        where id=(payload->>'grant_id')::uuid and user_id=actor and revoked_at is null for update;
      if not found then raise exception 'Writing approval required' using errcode='42501'; end if;
    end if;$old$,
       $new$    if not benchmark_private.oi_unapproved_drafts_enabled() then
      raise exception 'Story creation is paused; saved drafts and photos are preserved' using errcode='42501';
    end if;$new$),
      ($old$story.user_id<>actor or (story.grant_id is not null and story.grant_id is distinct from permission.id)$old$,
       $new$story.user_id<>actor$new$),
      ($old$    -- Claiming an approval for an existing temporary draft also consumes its quota.
    if permission.id is not null and story.grant_id is null then
      if (select count(*) from public.oi_stories where grant_id=permission.id)>=permission.story_limit then
        raise exception 'Approved story count exhausted' using errcode='42501';
      end if;
    end if;
$old$, ''),
      ($old$values(target,actor,actor,permission.id,$old$, $new$values(target,actor,actor,null,$new$),
      ($old$on conflict(id) do update set grant_id=excluded.grant_id,title=excluded.title$old$,
       $new$on conflict(id) do update set title=excluded.title$new$),
      ($old$    select * into permission from public.oi_writing_grants where id=story.grant_id for share;
$old$, ''),
      ($old$    if action<>'delete_story' and permission.revoked_at is not null then raise exception 'Writing approval revoked' using errcode='42501'; end if;
    if story.grant_id is null and not benchmark_private.oi_unapproved_drafts_enabled()
      and (action in ('attach_media','submit_story') or (action='review_story' and payload->>'status'='published')) then
      raise exception 'Writing approval required; saved drafts and photos are preserved' using errcode='42501';
    end if;$old$,
       $new$    if not benchmark_private.oi_unapproved_drafts_enabled()
      and (action in ('attach_media','submit_story') or (action='review_story' and payload->>'status'='published')) then
      raise exception 'Story creation is paused; saved drafts and photos are preserved' using errcode='42501';
    end if;$new$)
    ) as changes(before_text, after_text)
  loop
    if length(definition)-length(replace(definition,change.before_text,''))<>length(change.before_text) then
      raise exception 'oi_mutate drift requires review before independent story creation: %',
        left(btrim(change.before_text),96);
    end if;
    definition := replace(definition,change.before_text,change.after_text);
  end loop;
  if definition ~ '\m(permission|capacity)\M' then
    raise exception 'oi_mutate still references the former writing approval';
  end if;
  execute definition;
end; $patch$;

do $capability$
declare
  definition text := pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text := '''unapproved_drafts_enabled'', benchmark_private.oi_unapproved_drafts_enabled()';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'oi_capabilities drift requires review before independent story creation';
  end if;
  execute replace(definition,anchor,'''independent_story_creation'',true,'||anchor);
end; $capability$;

-- Keep the capability and operator pause switch compatible with existing clients.
-- The switch now pauses creation and publication uniformly for all accounts.
alter table benchmark_private.oi_story_creation_settings
  alter column unapproved_drafts_enabled set default true;
update benchmark_private.oi_story_creation_settings
  set unapproved_drafts_enabled=true,updated_at=now()
  where singleton and not unapproved_drafts_enabled;

create or replace function benchmark_private.oi_can_upload_story_media(story_id_text text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from benchmark_private.oi_story_creation_settings where singleton for share;
  return benchmark_private.oi_unapproved_drafts_enabled() and exists(
    select 1 from public.oi_stories s
    where s.id::text=story_id_text and s.user_id=benchmark_private.oi_actor() and s.status='draft'
  );
end; $$;

notify pgrst,'reload schema';
commit;

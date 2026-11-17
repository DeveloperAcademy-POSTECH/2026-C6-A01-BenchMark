begin;

-- Audited against both the repository and deployed-campus fixture histories.
-- Reject unknown ownership/publication changes before touching the schema.
do $drift$
begin
  if (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc where oid=
      'benchmark_private.oi_mutate_internal(text,jsonb,text)'::regprocedure)
      not in ('dd7aeb06bbe54ec3e32f81bbdb2069c4','fb98036b9acccd39966c098f2d01dfc8')
    or (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc where oid=
      'benchmark_private.oi_story_review_snapshot(jsonb)'::regprocedure)<>'0eea50dddc49bca3faca61c3a7965787'
    or (select md5(btrim(prosrc,E' \n\r\t')) from pg_proc where oid=
      'public.oi_capabilities()'::regprocedure)<>'2c5e9b3d79b3114a54305d180792215c' then
    raise exception 'Story continuation drift requires ownership and moderation review';
  end if;
end; $drift$;

-- A public story row must never expose the UUID of a hidden/deleted parent.
create table benchmark_private.oi_story_continuations (
  child_story_id uuid primary key references public.oi_stories(id) on delete cascade,
  parent_story_id uuid references public.oi_stories(id) on delete set null,
  published_at timestamptz,
  read_at timestamptz,
  check (child_story_id is distinct from parent_story_id)
);
create index oi_story_continuations_parent on benchmark_private.oi_story_continuations
  (parent_story_id,published_at desc,child_story_id desc) where parent_story_id is not null;
alter table benchmark_private.oi_story_continuations enable row level security;
revoke all on benchmark_private.oi_story_continuations from public,anon,authenticated;

create function benchmark_private.oi_check_continuation(p_child uuid,p_parent uuid,p_owner uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_parent is null then return; end if;
  -- Serialize topology edits, including two opposing edits that could form a cycle.
  perform pg_advisory_xact_lock(418,1);
  perform 1 from public.oi_stories s where s.id=p_parent and s.status='published'
    and s.user_id<>p_owner and not benchmark_private.oi_content_restricted(s.user_id) for share;
  if not found or p_parent=p_child then
    raise exception 'Continuation target unavailable' using errcode='22023';
  end if;
  if exists(with recursive ancestors(id) as (
      select p_parent union
      select c.parent_story_id from benchmark_private.oi_story_continuations c
        join ancestors a on a.id=c.child_story_id where c.parent_story_id is not null
    ) select 1 from ancestors where id=p_child) then
    raise exception 'Continuation cycle is not allowed' using errcode='22023';
  end if;
end;
$$;
revoke all on function benchmark_private.oi_check_continuation(uuid,uuid,uuid) from public,anon,authenticated,service_role;

-- Keep the audited implementation intact as a private delegate. Every caller,
-- including service-only automatic moderation, still enters the guarded wrapper.
do $copy$
declare definition text := pg_get_functiondef('benchmark_private.oi_mutate_internal(text,jsonb,text)'::regprocedure);
  anchor constant text := 'FUNCTION benchmark_private.oi_mutate_internal(';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'Story continuation mutation signature drift';
  end if;
  execute replace(definition,anchor,'FUNCTION benchmark_private.oi_mutate_continuation_base(');
end; $copy$;
revoke all on function benchmark_private.oi_mutate_continuation_base(text,jsonb,text) from public,anon,authenticated,service_role;

create or replace function benchmark_private.oi_mutate_internal(action text,payload jsonb,moderation_step text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; target uuid; parent uuid; owner_id uuid;
begin
  -- Always obtain the topology lock before the existing story row lock.
  if action in ('save_story','submit_story','delete_story','review_story') then
    perform pg_advisory_xact_lock(418,1);
  end if;
  result := benchmark_private.oi_mutate_continuation_base(action,payload,moderation_step);
  if action in ('save_story','attach_media','reopen_story','submit_story','review_story') then
    target := (result->>'id')::uuid;
    owner_id := (result->>'user_id')::uuid;
    select parent_story_id into parent from benchmark_private.oi_story_continuations where child_story_id=target;
    if action='save_story' and payload ? 'continued_from_story_id' then
      parent := (payload->>'continued_from_story_id')::uuid;
      perform benchmark_private.oi_check_continuation(target,parent,owner_id);
      insert into benchmark_private.oi_story_continuations as old(child_story_id,parent_story_id)
        values(target,parent)
      on conflict(child_story_id) do update set parent_story_id=excluded.parent_story_id,
        published_at=case when old.parent_story_id is distinct from excluded.parent_story_id then null else old.published_at end,
        read_at=case when old.parent_story_id is distinct from excluded.parent_story_id then null else old.read_at end;
    elsif action='submit_story' or (action='review_story' and payload->>'status'='published') then
      perform benchmark_private.oi_check_continuation(target,parent,owner_id);
    end if;
    -- Only the authenticated owner/mutation caller gets draft metadata; raw public rows do not.
    result := result || jsonb_build_object('continued_from_story_id',
      (select s.id from public.oi_stories s where s.id=parent and s.status='published'
        and s.user_id<>owner_id and not benchmark_private.oi_content_restricted(s.user_id)));
  end if;
  return result;
end;
$$;
revoke all on function benchmark_private.oi_mutate_internal(text,jsonb,text) from public,anon,authenticated,service_role;

do $copy$
declare definition text := pg_get_functiondef('benchmark_private.oi_story_review_snapshot(jsonb)'::regprocedure);
begin
  execute replace(definition,'FUNCTION benchmark_private.oi_story_review_snapshot(',
    'FUNCTION benchmark_private.oi_story_review_snapshot_continuation_base(');
end; $copy$;
revoke all on function benchmark_private.oi_story_review_snapshot_continuation_base(jsonb) from public,anon,authenticated,service_role;

create or replace function benchmark_private.oi_story_review_snapshot(p_submission jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare result jsonb; parent uuid;
begin
  result := benchmark_private.oi_story_review_snapshot_continuation_base(p_submission);
  select parent_story_id into parent from benchmark_private.oi_story_continuations
    where child_story_id=(p_submission->>'id')::uuid;
  -- Null relations keep existing approved snapshots byte-for-byte compatible.
  if parent is not null then
    result := jsonb_set(result,'{snapshot}',to_jsonb(encode(sha256(convert_to(
      jsonb_build_array(result->>'snapshot',parent)::text,'UTF8')),'hex')));
  end if;
  return result;
end;
$$;
revoke all on function benchmark_private.oi_story_review_snapshot(jsonb) from public,anon,authenticated,service_role;

create function benchmark_private.oi_continuation_story_change() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status='deleted' and old.status is distinct from new.status then
    update benchmark_private.oi_story_continuations set parent_story_id=null,published_at=null,read_at=null
      where parent_story_id=new.id;
  elsif new.status='published' and old.status is distinct from new.status then
    -- One durable in-app event per relation, even after retry/hide/republication.
    update benchmark_private.oi_story_continuations set published_at=coalesce(published_at,statement_timestamp())
      where child_story_id=new.id and parent_story_id is not null;
  end if;
  return new;
end;
$$;
revoke all on function benchmark_private.oi_continuation_story_change() from public,anon,authenticated,service_role;
create trigger oi_continuation_story_change after update of status on public.oi_stories
  for each row execute function benchmark_private.oi_continuation_story_change();

create function benchmark_private.oi_visible_continuations(p_blocked uuid[])
returns table(child_story_id uuid,parent_story_id uuid,published_at timestamptz,read_at timestamptz)
language sql stable security definer set search_path='' as $$
  select c.child_story_id,c.parent_story_id,c.published_at,c.read_at
  from benchmark_private.oi_story_continuations c
  join public.oi_stories child on child.id=c.child_story_id
  join public.oi_stories parent on parent.id=c.parent_story_id
  where child.status='published' and parent.status='published' and c.published_at is not null
    and child.user_id<>parent.user_id
    and not benchmark_private.oi_content_restricted(child.user_id)
    and not benchmark_private.oi_content_restricted(parent.user_id)
    and not (child.user_id=any(coalesce(p_blocked,'{}')))
    and not (parent.user_id=any(coalesce(p_blocked,'{}')));
$$;
revoke all on function benchmark_private.oi_visible_continuations(uuid[]) from public,anon,authenticated,service_role;

create function public.oi_story_continuations(p_parent uuid default null,p_mine boolean default false,
  p_before timestamptz default null,p_before_id uuid default null,p_blocked uuid[] default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid; answer jsonb;
begin
  if p_mine then
    if current_setting('role',true) not in ('authenticated','service_role') then
      raise exception 'Sign in required' using errcode='42501';
    end if;
    actor:=benchmark_private.oi_actor();
  elsif p_parent is null then raise exception 'Parent required' using errcode='22023'; end if;
  if cardinality(p_blocked)>500 or (p_before is null)<>(p_before_id is null) then
    raise exception 'Invalid continuation query' using errcode='22023';
  end if;
  with visible as (
    select c.* from benchmark_private.oi_visible_continuations(p_blocked) c
    join public.oi_stories p on p.id=c.parent_story_id
    where case when p_mine then p.user_id=actor else p.id=p_parent end
  ), page as (
    select * from visible where p_before is null or (published_at,child_story_id)<(p_before,p_before_id)
    order by published_at desc,child_story_id desc limit 20
  ) select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object(
      'child_story_id',child_story_id,'parent_story_id',parent_story_id,'published_at',published_at,
      'story',(select to_jsonb(s) from public.oi_stories s where s.id=child_story_id),
      'read_at',case when p_mine then read_at else null end) order by published_at desc,child_story_id desc) from page),'[]'::jsonb),
    'total',(select count(*) from visible),
    'next_cursor',case when (select count(*) from page)=20 then
      (select jsonb_build_object('published_at',published_at,'child_story_id',child_story_id)
      from page order by published_at,child_story_id limit 1) else null end) into answer;
  return answer;
end;
$$;
revoke all on function public.oi_story_continuations(uuid,boolean,timestamptz,uuid,uuid[]) from public;
grant execute on function public.oi_story_continuations(uuid,boolean,timestamptz,uuid,uuid[]) to anon,authenticated;

create function public.oi_story_continuation_counts(p_stories uuid[],p_blocked uuid[] default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if cardinality(p_stories)>200 or cardinality(p_blocked)>500 then
    raise exception 'Too many continuation targets' using errcode='22023';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('story_id',id,'count',total)),'[]'::jsonb)
    from (select p.id,count(c.child_story_id) as total from public.oi_stories p
      left join benchmark_private.oi_visible_continuations(p_blocked) c on c.parent_story_id=p.id
      where p.id=any(p_stories) and p.status='published'
        and not benchmark_private.oi_content_restricted(p.user_id)
        and not (p.user_id=any(coalesce(p_blocked,'{}')))
      group by p.id) counted);
end;
$$;
revoke all on function public.oi_story_continuation_counts(uuid[],uuid[]) from public;
grant execute on function public.oi_story_continuation_counts(uuid[],uuid[]) to anon,authenticated;

create function public.oi_my_story_continuation_targets() returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('story_id',c.child_story_id,
    'continued_from_story_id',case when p.status='published' and p.user_id<>child.user_id and not benchmark_private.oi_content_restricted(p.user_id)
      then p.id else null end)),'[]'::jsonb)
  from benchmark_private.oi_story_continuations c
  join public.oi_stories child on child.id=c.child_story_id
  left join public.oi_stories p on p.id=c.parent_story_id
  where child.user_id=benchmark_private.oi_account_id() and child.status<>'deleted';
$$;
revoke all on function public.oi_my_story_continuation_targets() from public,anon;
grant execute on function public.oi_my_story_continuation_targets() to authenticated;

create function public.oi_read_story_continuation(p_child uuid,p_blocked uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=benchmark_private.oi_actor(); result jsonb;
begin
  if cardinality(p_blocked)>500 then raise exception 'Too many blocked authors' using errcode='22023'; end if;
  select jsonb_build_object('child_story_id',v.child_story_id,'parent_story_id',v.parent_story_id,
    'published_at',v.published_at,'read_at',coalesce(v.read_at,statement_timestamp()),'story',to_jsonb(child)) into result
    from benchmark_private.oi_visible_continuations(p_blocked) v
    join public.oi_stories parent on parent.id=v.parent_story_id
    join public.oi_stories child on child.id=v.child_story_id
    where v.child_story_id=p_child and parent.user_id=actor;
  if result is null then raise exception 'Continuation unavailable' using errcode='22023'; end if;
  update benchmark_private.oi_story_continuations c set read_at=coalesce(c.read_at,statement_timestamp())
    where c.child_story_id=p_child;
  return result;
end;
$$;
revoke all on function public.oi_read_story_continuation(uuid,uuid[]) from public,anon;
grant execute on function public.oi_read_story_continuation(uuid,uuid[]) to authenticated;

do $capability$
declare definition text:=pg_get_functiondef('public.oi_capabilities()'::regprocedure);
  anchor constant text:='''story_card_cover_jpeg'',true';
begin
  if length(definition)-length(replace(definition,anchor,''))<>length(anchor) then
    raise exception 'Story continuation capability drift';
  end if;
  execute replace(definition,anchor,anchor||',''story_continuations'',true,''story_continuation_notifications'',true');
end; $capability$;

notify pgrst,'reload schema';
commit;

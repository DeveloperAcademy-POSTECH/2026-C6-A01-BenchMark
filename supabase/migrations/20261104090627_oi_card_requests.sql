begin;

-- Store the requesting auth member. Resolve its canonical account and the
-- story's current owner at read time so requests survive account merges.
create table benchmark_private.oi_card_requests (
  id uuid primary key,
  story_id uuid not null references public.oi_stories(id) on delete cascade,
  requester_member_id uuid not null references benchmark_private.oi_account_members(auth_user_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check ((status = 'pending') = (resolved_at is null)),
  check (resolved_at >= created_at)
);
create index oi_card_requests_story_idx on benchmark_private.oi_card_requests(story_id, created_at desc);
create index oi_card_requests_requester_idx on benchmark_private.oi_card_requests(requester_member_id, story_id, created_at desc);
alter table benchmark_private.oi_card_requests enable row level security;
revoke all on benchmark_private.oi_card_requests from public, anon, authenticated;

create view benchmark_private.oi_card_request_details with (security_invoker = true) as
select request.id, request.story_id, request.status, request.created_at,
       member.account_id as requester_id, story.user_id as owner_id,
       jsonb_build_object(
         'id', request.id, 'story_id', story.id, 'cucumber_name', story.cucumber_name,
         'story_title', story.title, 'cucumber_asset', story.cucumber_asset,
         'requester_name', requester.nickname, 'owner_name', owner.nickname,
         'requester_school_name', requester_school.name,
         'status', request.status, 'created_at', request.created_at, 'resolved_at', request.resolved_at
       ) as receipt
from benchmark_private.oi_card_requests request
join benchmark_private.oi_account_members member on member.auth_user_id = request.requester_member_id
join public.oi_stories story on story.id = request.story_id and story.status = 'published'
join public.oi_profiles requester on requester.id = member.account_id
left join public.oi_schools requester_school on requester_school.id = requester.school_id and exists (
  select 1 from public.oi_stories requester_story
  where requester_story.user_id = requester.id and requester_story.status = 'published'
)
join public.oi_profiles owner on owner.id = story.user_id;
revoke all on benchmark_private.oi_card_request_details from public, anon, authenticated;

create function benchmark_private.oi_list_card_requests() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := benchmark_private.oi_actor();
begin
  return (
    select coalesce(jsonb_agg(receipt order by created_at desc, id desc), '[]'::jsonb)
    from (
      select receipt, created_at, id
      from benchmark_private.oi_card_request_details
      where owner_id = actor and requester_id <> actor and status = 'pending'
      order by created_at desc, id desc
      limit 100
    ) pending
  );
end;
$$;
revoke all on function benchmark_private.oi_list_card_requests() from public, anon, authenticated;
grant execute on function benchmark_private.oi_list_card_requests() to authenticated;

create function public.oi_card_requests() returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_list_card_requests();
$$;
revoke all on function public.oi_card_requests() from public, anon, authenticated;
grant execute on function public.oi_card_requests() to authenticated;

create function benchmark_private.oi_request_card(p_story_id uuid, p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := benchmark_private.oi_actor();
  story_owner uuid;
  previous record;
begin
  if p_story_id is null or p_request_id is null then
    raise exception 'invalid_card_request' using errcode = '22023';
  end if;

  -- Match the lock order in account merge and story mutations: actor
  -- membership, story, then request. A withdrawn story cannot gain a request.
  select user_id into story_owner
    from public.oi_stories where id = p_story_id and status = 'published' for share;
  if not found then raise exception 'card_request_story_unavailable' using errcode = 'PT404'; end if;
  if story_owner = actor then raise exception 'card_request_self' using errcode = 'PT409'; end if;

  perform pg_advisory_xact_lock(hashtextextended(actor::text || ':' || p_story_id::text, 141));
  select request.story_id, member.account_id into previous
    from benchmark_private.oi_card_requests request
    join benchmark_private.oi_account_members member on member.auth_user_id = request.requester_member_id
    where request.id = p_request_id;
  if found then
    if previous.story_id <> p_story_id or previous.account_id <> actor then
      raise exception 'card_request_id_conflict' using errcode = 'PT409';
    end if;
    return (select receipt from benchmark_private.oi_card_request_details where id = p_request_id);
  end if;

  select receipt into previous
    from benchmark_private.oi_card_request_details
    where requester_id = actor and story_id = p_story_id and status = 'pending'
    order by created_at desc, id desc limit 1;
  if found then return previous.receipt; end if;

  -- The global primary key also rejects simultaneous replays of the same
  -- client ID across different accounts or stories.
  insert into benchmark_private.oi_card_requests (id, story_id, requester_member_id)
    values (p_request_id, p_story_id, auth.uid()) on conflict (id) do nothing;
  if not found then raise exception 'card_request_id_conflict' using errcode = 'PT409'; end if;

  return (select receipt from benchmark_private.oi_card_request_details where id = p_request_id);
end;
$$;
revoke all on function benchmark_private.oi_request_card(uuid, uuid) from public, anon, authenticated;
grant execute on function benchmark_private.oi_request_card(uuid, uuid) to authenticated;

create function public.oi_request_card(p_story_id uuid, p_request_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_request_card(p_story_id, p_request_id);
$$;
revoke all on function public.oi_request_card(uuid, uuid) from public, anon, authenticated;
grant execute on function public.oi_request_card(uuid, uuid) to authenticated;

create function benchmark_private.oi_resolve_card_request(p_request_id uuid, p_decision text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := benchmark_private.oi_actor();
  requested_story uuid;
  requester uuid;
  current_status text;
  wanted_status text;
begin
  if p_request_id is null or p_decision is null or p_decision not in ('accept', 'reject') then
    raise exception 'invalid_card_request_decision' using errcode = '22023';
  end if;
  wanted_status := case p_decision when 'accept' then 'accepted' else 'rejected' end;

  select story_id into requested_story from benchmark_private.oi_card_requests where id = p_request_id;
  perform 1 from public.oi_stories where id = requested_story and user_id = actor and status = 'published' for share;
  if not found then raise exception 'card_request_unavailable' using errcode = 'PT404'; end if;

  select request.status, member.account_id into current_status, requester
    from benchmark_private.oi_card_requests request
    join benchmark_private.oi_account_members member on member.auth_user_id = request.requester_member_id
    where request.id = p_request_id for update of request;
  if not found or requester = actor then raise exception 'card_request_unavailable' using errcode = 'PT404'; end if;

  if current_status = 'pending' then
    update benchmark_private.oi_card_requests
      set status = wanted_status, resolved_at = clock_timestamp()
      where id = p_request_id;
  elsif current_status <> wanted_status then
    raise exception 'card_request_already_resolved' using errcode = 'PT409';
  end if;

  return (select receipt from benchmark_private.oi_card_request_details where id = p_request_id);
end;
$$;
revoke all on function benchmark_private.oi_resolve_card_request(uuid, text) from public, anon, authenticated;
grant execute on function benchmark_private.oi_resolve_card_request(uuid, text) to authenticated;

create function public.oi_resolve_card_request(p_request_id uuid, p_decision text) returns jsonb
language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_resolve_card_request(p_request_id, p_decision);
$$;
revoke all on function public.oi_resolve_card_request(uuid, text) from public, anon, authenticated;
grant execute on function public.oi_resolve_card_request(uuid, text) to authenticated;

commit;

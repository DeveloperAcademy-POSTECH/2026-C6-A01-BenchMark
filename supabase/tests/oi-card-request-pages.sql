begin;

create function pg_temp.assert_true(result boolean, description text) returns void
language plpgsql as $$
begin
  if result is distinct from true then raise exception 'Card request assertion failed: %', description; end if;
end;
$$;
create function pg_temp.assert_error(command text, expected_state text) returns void
language plpgsql as $$
begin
  begin execute command;
  exception when others then
    if sqlstate = expected_state then return; end if;
    raise exception 'Expected %, got %: %', expected_state, sqlstate, sqlerrm;
  end;
  raise exception 'Expected error % for %', expected_state, command;
end;
$$;

\set owner 'd1410000-0000-4000-8000-000000000001'
\set requester 'd1410000-0000-4000-8000-000000000002'
\set stranger 'd1410000-0000-4000-8000-000000000003'
\set second_requester 'd1410000-0000-4000-8000-000000000004'
\set owner_session 'd1410000-0000-4000-8000-000000000011'
\set requester_session 'd1410000-0000-4000-8000-000000000012'
\set second_session 'd1410000-0000-4000-8000-000000000014'
\set story 'd1410000-0000-4000-8000-000000000021'
\set hidden_story 'd1410000-0000-4000-8000-000000000022'
\set other_story 'd1410000-0000-4000-8000-000000000023'
\set fresh_story 'd1410000-0000-4000-8000-000000000025'
\set request 'd1410000-0000-4000-8000-000000000031'
\set duplicate 'd1410000-0000-4000-8000-000000000032'
\set second_request 'd1410000-0000-4000-8000-000000000033'
\set post_merge_request 'd1410000-0000-4000-8000-000000000034'
\set evidence 'd1410000-0000-4000-8000-000000000041'
\set grant 'd1410000-0000-4000-8000-000000000051'
\set merge 'd1410000-0000-4000-8000-000000000061'

insert into auth.users (id) values (:'owner'), (:'requester'), (:'stranger'), (:'second_requester');
insert into auth.sessions (id, user_id) values
  (:'owner_session', :'owner'), (:'requester_session', :'requester'), (:'second_session', :'second_requester');
update public.oi_profiles set nickname = 'Synthetic owner' where id = :'owner';
update public.oi_profiles set nickname = 'Synthetic requester', school_id = 'postech' where id = :'requester';
insert into public.oi_evidence_requests (id, user_id, storage_owner_id, status)
  values (:'evidence', :'owner', :'owner', 'approved');
insert into public.oi_writing_grants (id, evidence_id, user_id, story_limit)
  values (:'grant', :'evidence', :'owner', 4);
insert into public.oi_stories
  (id, user_id, storage_owner_id, grant_id, region_id, title, body, theme, emotion, cucumber_name, cucumber_asset, card_asset, latitude, longitude, status)
select story_id, :'owner', :'owner', :'grant', 'pond', 'Synthetic title', 'Synthetic body', '감사', '기쁨', 'Synthetic cucumber',
  'OiCats', 'MYBasicCard', 36.01261057021347, 129.3197268697784, story_status
from (values (:'story'::uuid, 'published'), (:'hidden_story'::uuid, 'hidden'), (:'other_story'::uuid, 'published'), (:'fresh_story'::uuid, 'published')) seeds(story_id, story_status);

insert into benchmark_private.oi_card_requests(id, story_id, requester_member_id, created_at)
select gen_random_uuid(), :'story', :'requester', '2026-11-01 00:00:00.123456+00'::timestamptz
from generate_series(1, 101);
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select public.oi_card_request_page() as first_page \gset
select pg_temp.assert_true(jsonb_array_length(:'first_page'::jsonb -> 'items') = 100, 'the first page is bounded');
select public.oi_card_request_page(
  (:'first_page'::jsonb ->> 'next_before')::timestamptz,
  (:'first_page'::jsonb ->> 'next_before_id')::uuid
) as second_page \gset
select pg_temp.assert_true(jsonb_array_length(:'second_page'::jsonb -> 'items') = 1
  and (:'second_page'::jsonb ->> 'next_before_id') is null,
  'the last request remains reachable when all timestamps are identical');
select pg_temp.assert_true(not exists (
  select 1 from jsonb_array_elements(:'first_page'::jsonb -> 'items') item
  where item ->> 'id' = :'second_page'::jsonb -> 'items' -> 0 ->> 'id'
), 'the keyset does not repeat rows');
select pg_temp.assert_error('select public.oi_card_request_page(now())', '22023');
select set_config('request.jwt.claim.sub', :'requester', true);
select pg_temp.assert_true(public.oi_card_request_page() -> 'items' = '[]'::jsonb, 'requester cannot read outgoing pages');
set local role anon;
select pg_temp.assert_error('select public.oi_card_request_page()', '42501');
reset role;

rollback;

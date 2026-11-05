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

set local role anon;
select pg_temp.assert_error('select public.oi_card_requests()', '42501');
select pg_temp.assert_error(format('select public.oi_request_card(%L, %L)', :'story', :'request'), '42501');
select pg_temp.assert_error(format('select public.oi_resolve_card_request(%L, %L)', :'request', 'accept'), '42501');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.assert_error('select public.oi_card_requests()', 'PT401');
select set_config('request.jwt.claim.sub', :'requester', true);
select pg_temp.assert_error('select * from benchmark_private.oi_card_requests', '42501');
select pg_temp.assert_error('select * from benchmark_private.oi_card_request_details', '42501');
select pg_temp.assert_error(format('select public.oi_request_card(%L, %L)', :'hidden_story', :'request'), 'PT404');
select public.oi_request_card(:'story', :'request') as receipt \gset
select pg_temp.assert_true(:'receipt'::jsonb ->> 'id' = :'request'
  and :'receipt'::jsonb ->> 'requester_name' = 'Synthetic requester'
  and :'receipt'::jsonb ->> 'requester_school_name' is null
  and :'receipt'::jsonb ->> 'status' = 'pending'
  and not (:'receipt'::jsonb ?| array['requester_member_id', 'requester_id', 'owner_id', 'body', 'expires_at']), 'receipt contains only authorized summary');
select pg_temp.assert_true(public.oi_request_card(:'story', :'request') = :'receipt'::jsonb
  and public.oi_request_card(:'story', :'duplicate') = :'receipt'::jsonb, 'retries and repeated taps do not create duplicate requests');
select pg_temp.assert_error(format('select public.oi_request_card(%L, %L)', :'other_story', :'request'), 'PT409');
select pg_temp.assert_true(public.oi_card_requests() = '[]'::jsonb, 'requester cannot see their own outgoing request in the inbox');
select pg_temp.assert_error(format('select public.oi_resolve_card_request(%L, %L)', :'request', 'accept'), 'PT404');
select pg_temp.assert_true((select count(*) = 0 from public.oi_collections), 'pending requests grant no collection');

select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.assert_true(public.oi_card_requests() -> 0 ->> 'id' = :'request', 'story owner sees request in the inbox');
select pg_temp.assert_error(format('select public.oi_resolve_card_request(%L, %L)', :'request', 'unknown'), '22023');
select pg_temp.assert_error(format('select public.oi_request_card(%L, %L)', :'story', :'duplicate'), 'PT409');

select set_config('request.jwt.claim.sub', :'stranger', true);
select pg_temp.assert_true(public.oi_card_requests() = '[]'::jsonb, 'unrelated account cannot list requests');
select pg_temp.assert_error(format('select public.oi_resolve_card_request(%L, %L)', :'request', 'reject'), 'PT404');
select pg_temp.assert_error(format('select public.oi_request_card(%L, %L)', :'story', :'request'), 'PT409');

select set_config('request.jwt.claim.sub', :'second_requester', true);
select public.oi_request_card(:'story', :'second_request');
select public.oi_request_card(:'other_story', :'duplicate');
reset role;

-- A requester with a public story may have their existing public school shown.
insert into public.oi_evidence_requests (id, user_id, storage_owner_id, status)
  values ('d1410000-0000-4000-8000-000000000042', :'requester', :'requester', 'approved');
insert into public.oi_writing_grants (id, evidence_id, user_id, story_limit)
  values ('d1410000-0000-4000-8000-000000000052', 'd1410000-0000-4000-8000-000000000042', :'requester', 1);
insert into public.oi_stories
  (id, user_id, storage_owner_id, grant_id, region_id, title, body, theme, emotion, cucumber_name, cucumber_asset, card_asset, latitude, longitude, status)
select 'd1410000-0000-4000-8000-000000000024', :'requester', :'requester', 'd1410000-0000-4000-8000-000000000052',
  region_id, title, body, theme, emotion, cucumber_name, cucumber_asset, card_asset, latitude, longitude, status
from public.oi_stories where id = :'story';

set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.assert_true(exists (
  select 1 from jsonb_array_elements(public.oi_card_requests()) request
  where request ->> 'id' = :'request' and length(request ->> 'requester_school_name') > 0
), 'public requester school appears in the inbox');
reset role;
set local role service_role;
select public.oi_merge_accounts('preview', :'merge', :'requester', :'second_requester',
  :'requester_session', :'second_session') ->> 'challenge_id' as challenge \gset
select public.oi_merge_accounts('confirm', :'merge', :'requester', :'second_requester',
  :'requester_session', :'second_session', :'challenge', true);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', :'second_requester', true);
select set_config('request.jwt.claims', jsonb_build_object('session_id', :'second_session')::text, true);
select pg_temp.assert_true(public.oi_card_requests() = '[]'::jsonb, 'merging requester accounts does not give them an inbox');
select pg_temp.assert_true(public.oi_request_card(:'story', :'second_request') ->> 'requester_name' = 'Synthetic requester',
  'retry under a merged member returns the canonical profile name');
select public.oi_request_card(:'fresh_story', :'post_merge_request');
reset role;
select pg_temp.assert_true((select requester_member_id = :'second_requester'
  from benchmark_private.oi_card_requests where id = :'post_merge_request'),
  'creation by an alias only locks the auth membership already held by the caller');

update public.oi_stories set status = 'hidden' where id in (:'other_story', :'fresh_story');
update benchmark_private.oi_card_requests set created_at = now() - interval '45 days' where id = :'request';
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.assert_true(jsonb_array_length(public.oi_card_requests()) = 2, 'withdrawn stories disappear and older pending requests remain');
select pg_temp.assert_error(format('select public.oi_resolve_card_request(%L, %L)', :'duplicate', 'accept'), 'PT404');
select public.oi_resolve_card_request(:'request', 'accept') as accepted \gset
select pg_temp.assert_true(:'accepted'::jsonb ->> 'status' = 'accepted'
  and :'accepted'::jsonb ->> 'resolved_at' is not null, 'accept records a status and decision time');
select pg_temp.assert_true(public.oi_resolve_card_request(:'request', 'accept') = :'accepted'::jsonb, 'same-decision retry returns the stored decision');
select pg_temp.assert_error(format('select public.oi_resolve_card_request(%L, %L)', :'request', 'reject'), 'PT409');
select pg_temp.assert_true(jsonb_array_length(public.oi_card_requests()) = 1, 'accept removes only the resolved request from the pending inbox');
select pg_temp.assert_true(public.oi_resolve_card_request(:'second_request', 'reject') ->> 'status' = 'rejected', 'reject records a separate decision');
select pg_temp.assert_true(public.oi_card_requests() = '[]'::jsonb, 'resolved requests leave the pending inbox');
reset role;

select pg_temp.assert_true((select count(*) = 0 from public.oi_collections), 'decisions do not add or transfer collections');
select pg_temp.assert_true((select user_id = :'owner' from public.oi_stories where id = :'story'), 'decisions preserve story ownership');
select pg_temp.assert_true((select count(*) = 4 from benchmark_private.oi_card_requests), 'decisions are retained without changing other requests');

rollback;

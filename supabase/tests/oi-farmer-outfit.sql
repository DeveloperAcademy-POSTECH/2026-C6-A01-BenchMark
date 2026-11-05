begin;

create function pg_temp.assert_true(result boolean, description text) returns void
language plpgsql as $$ begin
  if result is distinct from true then raise exception 'Farmer outfit assertion failed: %', description; end if;
end; $$;
create function pg_temp.assert_error(command text, expected_state text) returns void
language plpgsql as $$ begin
  begin execute command;
  exception when others then
    if sqlstate = expected_state then return; end if;
    raise exception 'Expected %, got %: %', expected_state, sqlstate, sqlerrm;
  end;
  raise exception 'Expected error % for %', expected_state, command;
end; $$;

\set owner 'f1590000-0000-4000-8000-000000000001'
\set other 'f1590000-0000-4000-8000-000000000002'
\set unused 'f1590000-0000-4000-8000-000000000003'
\set owner_session 'f1590000-0000-4000-8000-000000000011'
\set other_session 'f1590000-0000-4000-8000-000000000012'
\set unused_session 'f1590000-0000-4000-8000-000000000013'
\set outfit '{"version":1,"character":"kyu","slots":{"top":"kyu-3916-2673","bottom":"kyu-bottom","shoes":"kyu-shoes"}}'
\set other_outfit '{"version":1,"character":"cumber","slots":{"set":"legacy-classic"}}'

insert into auth.users(id) values (:'owner'), (:'other'), (:'unused');
insert into auth.sessions(id, user_id) values
  (:'owner_session', :'owner'), (:'other_session', :'other'), (:'unused_session', :'unused');
select pg_temp.assert_true((select relrowsecurity from pg_class
  where oid = 'benchmark_private.oi_farmer_outfits'::regclass), 'outfit table enables RLS');
select pg_temp.assert_true(not exists(select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'oi_profiles' and column_name = 'farmer_outfit'),
  'public profiles do not expose account outfits');

set local role anon;
select pg_temp.assert_error('select public.oi_farmer_outfit()', '42501');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{}}')$q$, '42501');
select pg_temp.assert_error('select * from benchmark_private.oi_farmer_outfits', '42501');

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.assert_error('select public.oi_farmer_outfit()', 'PT401');
select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.assert_true((public.oi_capabilities() ->> 'farmer_outfit_enabled')::boolean,
  'capability advertises the installed outfit RPCs');
select pg_temp.assert_true(public.oi_farmer_outfit() = jsonb_build_object('account_id', :'owner', 'outfit', null),
  'new and existing accounts initially have no server outfit');
select public.oi_save_farmer_outfit(:'outfit') as saved \gset
select pg_temp.assert_true(:'saved'::jsonb ->> 'account_id' = :'owner' and :'saved'::jsonb -> 'outfit' = :'outfit'::jsonb,
  'outfit save returns the canonical owner and exact versioned value');
select pg_temp.assert_true(public.oi_farmer_outfit() -> 'outfit' = :'outfit'::jsonb,
  'a separate read restores the saved outfit');
select pg_temp.assert_error('select * from benchmark_private.oi_farmer_outfits', '42501');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":2,"character":"kyu","slots":{}}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"character":"kyu","slots":{}}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"classic","slots":{}}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"cape":"cape"}}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"hat":42}}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":[]}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"hat":"https://example.invalid/asset"}}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"hat":"../asset"}}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"hat":"UPPERCASE"}}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"hat":"two words"}}')$q$, '22023');
select pg_temp.assert_error(format('select public.oi_save_farmer_outfit(%L)',
  jsonb_build_object('version', 1, 'character', 'kyu', 'slots', jsonb_build_object('hat', repeat('a', 81)))::text), '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{},"account_id":"someone-else"}')$q$, '22023');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit(null)$q$, '22023');
select pg_temp.assert_true(public.oi_farmer_outfit() -> 'outfit' = :'outfit'::jsonb,
  'invalid saves never overwrite the last valid outfit');
select public.oi_update_school_profile('postech', 2020, 'Physics');
update public.oi_profiles set farm_name = '개별농장' where id = auth.uid();
select pg_temp.assert_true(public.oi_farmer_outfit() -> 'outfit' = :'outfit'::jsonb,
  'farm name and school edits do not overwrite an outfit');

select set_config('request.jwt.claim.sub', :'other', true);
select pg_temp.assert_true(public.oi_farmer_outfit() -> 'outfit' = 'null'::jsonb,
  'another account does not read the first outfit');
select public.oi_save_farmer_outfit(:'other_outfit');
reset role;
select pg_temp.assert_true((select count(*) = 2 from benchmark_private.oi_farmer_outfits),
  'outfits remain separate records for separate accounts');

set local role service_role;
select public.oi_merge_accounts('preview', 'f1590000-0000-4000-8000-000000000021',
  :'owner', :'other', :'owner_session', :'other_session') as merge_preview \gset
select pg_temp.assert_true((:'merge_preview'::jsonb ->> 'source_is_new')::boolean is false,
  'a saved outfit is not classified as an unused login method');
select public.oi_merge_accounts('preview', 'f1590000-0000-4000-8000-000000000022',
  :'owner', :'unused', :'owner_session', :'unused_session') as unused_preview \gset
select pg_temp.assert_true((:'unused_preview'::jsonb ->> 'source_is_new')::boolean,
  'accounts with no saved outfit retain new-login-method classification');
select public.oi_merge_accounts('confirm', 'f1590000-0000-4000-8000-000000000021',
  :'owner', :'other', :'owner_session', :'other_session',
  (:'merge_preview'::jsonb ->> 'challenge_id')::uuid, true);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'other', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.assert_error('select public.oi_farmer_outfit()', 'PT401');
select pg_temp.assert_error($q$select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{}}')$q$, 'PT401');
select set_config('request.jwt.claims', jsonb_build_object('session_id', :'other_session')::text, true);
select pg_temp.assert_true(public.oi_farmer_outfit() = jsonb_build_object('account_id', :'owner', 'outfit', :'outfit'::jsonb),
  'an approved merged member uses the chosen representative outfit');
select public.oi_save_farmer_outfit('{"version":1,"character":"kyu","slots":{"hat":"kyu-hat"}}');
reset role;
select pg_temp.assert_true((select outfit -> 'slots' ->> 'hat' = 'kyu-hat'
  from benchmark_private.oi_farmer_outfits where account_id = :'owner'), 'merged edits save only to the canonical account');
select pg_temp.assert_true((select outfit = :'other_outfit'::jsonb
  from benchmark_private.oi_farmer_outfits where account_id = :'other'), 'secondary account outfit is preserved');

rollback;

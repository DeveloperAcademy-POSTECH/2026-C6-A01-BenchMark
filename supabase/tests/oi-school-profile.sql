begin;

create function pg_temp.assert_true(result boolean, description text) returns void
language plpgsql as $$ begin
  if result is distinct from true then raise exception 'School profile assertion failed: %', description; end if;
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

\set owner 'e1580000-0000-4000-8000-000000000001'
\set other 'e1580000-0000-4000-8000-000000000002'
\set owner_session 'e1580000-0000-4000-8000-000000000011'
\set other_session 'e1580000-0000-4000-8000-000000000012'
\set operation 'e1580000-0000-4000-8000-000000000021'

insert into auth.users (id) values (:'owner'), (:'other');
insert into auth.sessions (id, user_id) values (:'owner_session', :'owner'), (:'other_session', :'other');
insert into public.oi_schools (id, name) values ('school-profile-158', 'Synthetic other school');

select pg_temp.assert_true(not exists (
  select 1 from information_schema.columns
  where table_schema = 'public' and table_name = 'oi_profiles' and column_name in ('school_admission_year', 'school_department')
), 'public author profiles have no private academic columns');
select pg_temp.assert_true((select relrowsecurity from pg_class
  where oid = 'benchmark_private.oi_school_profile_metadata'::regclass), 'private metadata enables RLS');

set local role anon;
select pg_temp.assert_error('select public.oi_school_profile()', '42501');
select pg_temp.assert_error($command$select public.oi_update_school_profile('postech', 2020, null)$command$, '42501');
select pg_temp.assert_error('select * from benchmark_private.oi_school_profile_metadata', '42501');

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.assert_error('select public.oi_school_profile()', 'PT401');
select set_config('request.jwt.claim.sub', :'owner', true);
select pg_temp.assert_true((public.oi_capabilities() ->> 'school_profile_enabled')::boolean,
  'capability advertises the installed school profile RPCs');
select pg_temp.assert_true(public.oi_school_profile() ->> 'id' = :'owner'
  and public.oi_school_profile() ->> 'school_admission_year' is null
  and public.oi_school_profile() ->> 'school_department' is null, 'legacy accounts have optional metadata');
update public.oi_profiles set public_name = 'Public donor', department = 'Public department', admission_year = '26'
where id = auth.uid();
select public.oi_update_school_profile('postech', 2020, '  Computer Science  ') as initial \gset
select pg_temp.assert_true(:'initial'::jsonb ->> 'id' = :'owner'
  and :'initial'::jsonb ->> 'school_id' = 'postech'
  and (:'initial'::jsonb ->> 'school_admission_year')::integer = 2020
  and :'initial'::jsonb ->> 'school_department' = 'Computer Science', 'school and trimmed metadata save atomically');
select pg_temp.assert_true(:'initial'::jsonb ->> 'public_name' = 'Public donor'
  and :'initial'::jsonb ->> 'admission_year' = '26'
  and :'initial'::jsonb ->> 'department' = 'Public department',
  'private school RPC preserves public donor fields in its JSON receipt');
select pg_temp.assert_true((select public_name = 'Public donor' and admission_year = '26' and department = 'Public department'
  from public.oi_profiles where id = auth.uid()), 'private school update never changes public donor metadata');
update public.oi_profiles set public_name = 'Edited public donor', admission_year = '25', department = 'Public History'
where id = auth.uid();
select pg_temp.assert_true(public.oi_school_profile() ->> 'admission_year' = '25'
  and public.oi_school_profile() ->> 'department' = 'Public History'
  and (public.oi_school_profile() ->> 'school_admission_year')::integer = 2020
  and public.oi_school_profile() ->> 'school_department' = 'Computer Science',
  'public donor edits preserve separate private academic metadata');
select pg_temp.assert_true(not (select to_jsonb(profile) ?| array['school_admission_year', 'school_department']
  from public.oi_profiles profile where id = auth.uid()), 'public profile responses never include private metadata');
select pg_temp.assert_error('select * from benchmark_private.oi_school_profile_metadata', '42501');
select pg_temp.assert_error($command$update public.oi_profiles set school_admission_year = 2021 where id = auth.uid()$command$, '42703');

-- Existing independent edits must preserve the new values.
update public.oi_profiles set nickname = 'Synthetic school owner' where id = auth.uid();
update public.oi_profiles set school_id = 'postech' where id = auth.uid();
select pg_temp.assert_true(public.oi_school_profile() ->> 'nickname' = 'Synthetic school owner'
  and public.oi_school_profile() ->> 'school_department' = 'Computer Science'
  and (public.oi_school_profile() ->> 'school_admission_year')::integer = 2020,
  'legacy nickname and school PATCHes preserve private metadata');
update public.oi_profiles set school_id = 'school-profile-158' where id = auth.uid();
select pg_temp.assert_true(public.oi_school_profile() ->> 'school_id' = 'school-profile-158'
  and public.oi_school_profile() ->> 'school_admission_year' is null
  and public.oi_school_profile() ->> 'school_department' is null,
  'a legacy school change never displays academic metadata from the previous school');
update public.oi_profiles set school_id = 'postech' where id = auth.uid();
select pg_temp.assert_true(public.oi_school_profile() ->> 'school_department' = 'Computer Science'
  and (public.oi_school_profile() ->> 'school_admission_year')::integer = 2020,
  'preserved metadata is readable only when its original school is selected again');
select pg_temp.assert_error($command$select public.oi_update_school_profile('postech', 1899, 'Physics')$command$, '22023');
select pg_temp.assert_error(format('select public.oi_update_school_profile(%L, %s, %L)',
  'postech', extract(year from timezone('UTC', now()))::integer + 1, 'Physics'), '22023');
select pg_temp.assert_error($command$select public.oi_update_school_profile('postech', null, 'Physics')$command$, '22023');
select pg_temp.assert_error($command$select public.oi_update_school_profile('missing-school', 2021, 'Physics')$command$, '22023');
select pg_temp.assert_error(format('select public.oi_update_school_profile(%L, 2021, %L)', 'postech', repeat('x', 101)), '22023');
select pg_temp.assert_error($command$select public.oi_update_school_profile('postech', 2021, E' \t\n ')$command$, '22023');
select pg_temp.assert_true(public.oi_school_profile() ->> 'school_id' = 'postech'
  and public.oi_school_profile() ->> 'school_department' = 'Computer Science'
  and (public.oi_school_profile() ->> 'school_admission_year')::integer = 2020,
  'invalid submissions preserve both public school and private metadata');

select public.oi_update_school_profile('postech', 2019, null);
select pg_temp.assert_true(public.oi_school_profile() -> 'school_department' = 'null'::jsonb
  and (public.oi_school_profile() ->> 'school_admission_year')::integer = 2019,
  'an explicit skipped department clears its previous value');

select set_config('request.jwt.claim.sub', :'other', true);
select pg_temp.assert_true(public.oi_school_profile() ->> 'id' = :'other'
  and public.oi_school_profile() ->> 'school_admission_year' is null
  and public.oi_school_profile() ->> 'school_department' is null, 'another account cannot read the first account metadata');
select public.oi_update_school_profile('postech', 2021, 'Physics');
reset role;
select pg_temp.assert_true((select count(*) = 2 from benchmark_private.oi_school_profile_metadata),
  'account writes retain separate metadata records');

-- The existing merge policy preserves the chosen representative's profile.
set local role service_role;
select public.oi_merge_accounts('preview', :'operation', :'owner', :'other', :'owner_session', :'other_session')
  ->> 'challenge_id' as challenge \gset
select public.oi_merge_accounts('confirm', :'operation', :'owner', :'other', :'owner_session', :'other_session', :'challenge', true);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'other', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.assert_error('select public.oi_school_profile()', 'PT401');
select pg_temp.assert_error($command$select public.oi_update_school_profile('postech', 2022, 'Engineering')$command$, 'PT401');
select set_config('request.jwt.claims', '{"session_id":"e1580000-0000-4000-8000-000000000099"}', true);
select pg_temp.assert_error('select public.oi_school_profile()', 'PT401');
select pg_temp.assert_error($command$select public.oi_update_school_profile('postech', 2022, 'Engineering')$command$, 'PT401');
select set_config('request.jwt.claims', jsonb_build_object('session_id', :'other_session')::text, true);
select pg_temp.assert_true(public.oi_school_profile() ->> 'id' = :'owner'
  and (public.oi_school_profile() ->> 'school_admission_year')::integer = 2019
  and public.oi_school_profile() -> 'school_department' = 'null'::jsonb,
  'a verified merged member reads only the representative account metadata');
select public.oi_update_school_profile('postech', 2022, 'Engineering');
reset role;
select pg_temp.assert_true((select admission_year = 2022 and department = 'Engineering'
  from benchmark_private.oi_school_profile_metadata where account_id = :'owner'),
  'merged-member edits update the canonical account');
select pg_temp.assert_true((select admission_year = 2021 and department = 'Physics'
  from benchmark_private.oi_school_profile_metadata where account_id = :'other'),
  'merged-member edits never overwrite another stored profile');

rollback;

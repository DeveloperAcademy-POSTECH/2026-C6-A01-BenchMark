begin;

create function pg_temp.assert_true(result boolean, description text) returns void
language plpgsql as $$ begin
  if result is distinct from true then raise exception 'Farm name assertion failed: %', description; end if;
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

\set legacy 'f1580000-0000-4000-8000-000000000001'
\set other 'f1580000-0000-4000-8000-000000000002'
\set customized 'f1580000-0000-4000-8000-000000000003'
\set unused 'f1580000-0000-4000-8000-000000000004'
\set legacy_session 'f1580000-0000-4000-8000-000000000011'
\set other_session 'f1580000-0000-4000-8000-000000000012'
\set customized_session 'f1580000-0000-4000-8000-000000000013'
\set unused_session 'f1580000-0000-4000-8000-000000000014'

select pg_temp.assert_true((select farm_name = '오이' and nickname = 'Legacy nickname'
  from public.oi_profiles where id = :'legacy'), 'migration sets the default without copying or changing a legacy nickname');
insert into auth.users (id) values (:'other'), (:'customized'), (:'unused');
insert into auth.sessions (id, user_id) values
  (:'legacy_session', :'legacy'), (:'other_session', :'other'),
  (:'customized_session', :'customized'), (:'unused_session', :'unused');
select pg_temp.assert_true((select farm_name = '오이' and nickname = '농부'
  from public.oi_profiles where id = :'other'), 'new accounts have independent default values');
select pg_temp.assert_true(has_column_privilege('anon', 'public.oi_profiles', 'farm_name', 'select'),
  'farm names follow the existing publicly readable author-profile scope');

set local role anon;
select pg_temp.assert_error($command$update public.oi_profiles set farm_name = '금지'$command$, '42501');

set local role authenticated;
select set_config('request.jwt.claim.sub', :'legacy', true);
select set_config('request.jwt.claims', '{}', true);
update public.oi_profiles set farm_name = E' \t새 농장\n ' where id = auth.uid();
select pg_temp.assert_true((select farm_name = '새 농장' and nickname = 'Legacy nickname'
  from public.oi_profiles where id = auth.uid()), 'farm-only edits trim whitespace without mutating the nickname');
select public.oi_update_school_profile('postech', 2020, 'Physics');
select pg_temp.assert_true(public.oi_school_profile() ->> 'farm_name' = '새 농장',
  'private school profile RPC roundtrips preserve the independent farm name');
update public.oi_profiles set nickname = 'Legacy edit' where id = auth.uid();
select pg_temp.assert_true((select farm_name = '새 농장' and nickname = 'Legacy edit'
  from public.oi_profiles where id = auth.uid()), 'old nickname-only PATCHes do not overwrite farm names');
update public.oi_profiles set farm_name = '우리들의농장' where id = auth.uid();
select pg_temp.assert_true((select char_length(farm_name) = 6 from public.oi_profiles where id = auth.uid()),
  'six normalized Korean scalars are supported');
update public.oi_profiles set farm_name = repeat(U&'\1100\1161', 6) where id = auth.uid();
select pg_temp.assert_true((select farm_name = '가가가가가가' from public.oi_profiles where id = auth.uid()),
  'decomposed Hangul is normalized before checking the six-scalar limit');
update public.oi_profiles set farm_name = repeat(U&'e\0301', 6) where id = auth.uid();
select pg_temp.assert_true((select farm_name = repeat(U&'\00E9', 6) and char_length(farm_name) = 6
  from public.oi_profiles where id = auth.uid()), 'canonical equivalents share one length boundary');
update public.oi_profiles set farm_name = repeat('🌱', 6) where id = auth.uid();
select pg_temp.assert_true((select char_length(farm_name) = 6 from public.oi_profiles where id = auth.uid()),
  'supplementary Unicode scalars are counted once');
select pg_temp.assert_error($command$update public.oi_profiles set farm_name = '1234567' where id = auth.uid()$command$, '23514');
select pg_temp.assert_error($command$update public.oi_profiles set farm_name = E' \t\n ' where id = auth.uid()$command$, '23514');
select pg_temp.assert_error($command$update public.oi_profiles set farm_name = U&'\00A0\3000' where id = auth.uid()$command$, '23514');
select pg_temp.assert_error($command$update public.oi_profiles set farm_name = null where id = auth.uid()$command$, '23502');
select pg_temp.assert_true((select farm_name = repeat('🌱', 6) from public.oi_profiles where id = auth.uid()),
  'invalid edits preserve the previously stored farm name');
update public.oi_profiles set farm_name = '대표농장' where id = auth.uid();
update public.oi_profiles set farm_name = '침범' where id = :'other';
reset role;
select pg_temp.assert_true((select farm_name = '오이' from public.oi_profiles where id = :'other'),
  'another account cannot edit an unrelated farm name');

set local role authenticated;
select set_config('request.jwt.claim.sub', :'customized', true);
update public.oi_profiles set farm_name = '별농장' where id = auth.uid();
reset role;
set local role service_role;
select public.oi_merge_accounts('preview', 'f1580000-0000-4000-8000-000000000021',
  :'legacy', :'customized', :'legacy_session', :'customized_session') as customized_preview \gset
select pg_temp.assert_true((:'customized_preview'::jsonb ->> 'source_is_new')::boolean is false,
  'a customized farm is not classified as an unused login method');
select public.oi_merge_accounts('preview', 'f1580000-0000-4000-8000-000000000022',
  :'legacy', :'unused', :'legacy_session', :'unused_session') as unused_preview \gset
select pg_temp.assert_true((:'unused_preview'::jsonb ->> 'source_is_new')::boolean,
  'untouched default farms retain the existing new-login-method classification');
select public.oi_merge_accounts('confirm', 'f1580000-0000-4000-8000-000000000021',
  :'legacy', :'customized', :'legacy_session', :'customized_session',
  (:'customized_preview'::jsonb ->> 'challenge_id')::uuid, true);
reset role;
select pg_temp.assert_true((select farm_name = '대표농장' from public.oi_profiles where id = :'legacy'),
  'the chosen representative account keeps its farm name');
select pg_temp.assert_true((select farm_name = '별농장' from public.oi_profiles where id = :'customized'),
  'merging accounts does not rewrite the secondary profile');
set local role authenticated;
select set_config('request.jwt.claim.sub', :'customized', true);
select set_config('request.jwt.claims', '{}', true);
update public.oi_profiles set farm_name = '차단' where id = :'legacy';
reset role;
select pg_temp.assert_true((select farm_name = '대표농장' from public.oi_profiles where id = :'legacy'),
  'a session that was not approved for the merge cannot mutate the canonical farm');
set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('session_id', :'customized_session')::text, true);
update public.oi_profiles set farm_name = '합친농장' where id = :'legacy';
select pg_temp.assert_true((select farm_name = '합친농장' from public.oi_profiles where id = :'legacy'),
  'an approved merged session edits only the canonical profile');

rollback;

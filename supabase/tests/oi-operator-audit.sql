begin;
create function pg_temp.assert_true(result boolean, description text) returns void language plpgsql as $$ begin
  if result is distinct from true then raise exception 'FAIL: %',description; end if;
end; $$;
create function pg_temp.assert_error(command text, expected_state text) returns void language plpgsql as $$ begin
  begin execute command;
  exception when others then
    if sqlstate=expected_state then return; end if;
    raise exception 'Unexpected SQLSTATE %, expected %',sqlstate,expected_state;
  end;
  raise exception 'Expected SQLSTATE %',expected_state;
end; $$;
insert into auth.users(id) values('a1450000-0000-4000-8000-000000000001'),('a1450000-0000-4000-8000-000000000002');
insert into benchmark_private.oi_operators values('a1450000-0000-4000-8000-000000000001');
insert into benchmark_private.oi_audit(id,actor_id,action,target_id,created_at) overriding system value
select 9007199254740990+n,'a1450000-0000-4000-8000-000000000001',
  case when n%3=0 then 'review_story' when n%3=1 then 'review_evidence:approved' else 'merge_accounts' end,
  'a1450000-0000-4000-8000-000000000003','2026-11-01T02:00:00Z' from generate_series(1,52) n;
insert into benchmark_private.oi_audit(actor_id,action,target_id,created_at) values
 ('a1450000-0000-4000-8000-000000000001','review_story','a1450000-0000-4000-8000-000000000003','2026-10-31T23:59:59Z'),
 ('a1450000-0000-4000-8000-000000000001','review_story','a1450000-0000-4000-8000-000000000003','2026-11-02T00:00:00Z');
set local role anon;
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z')$q$,'42501');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1450000-0000-4000-8000-000000000002',true);
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z')$q$,'42501');
select set_config('request.jwt.claim.sub','a1450000-0000-4000-8000-000000000001',true);
select pg_temp.assert_error('select * from benchmark_private.oi_audit','42501');
select pg_temp.assert_error($q$insert into benchmark_private.oi_audit(actor_id,action,target_id) values(auth.uid(),'forged',auth.uid())$q$,'42501');
select pg_temp.assert_error($q$select public.oi_operator_audit(null,'2026-11-02Z')$q$,'22023');
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-02Z','2026-11-01Z')$q$,'22023');
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-09-01Z','2026-11-02Z')$q$,'22023');
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z',p_limit=>51)$q$,'22023');
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z',p_limit=>null)$q$,'22023');
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z',p_category=>'invalid')$q$,'22023');
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z',p_cursor_id=>1)$q$,'22023');
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z',p_cursor_at=>'2026-10-31Z',p_cursor_id=>1)$q$,'22023');
select set_config('test.audit.first',public.oi_operator_audit('2026-11-01Z','2026-11-02Z')::text,true);
select pg_temp.assert_true(jsonb_array_length(current_setting('test.audit.first')::jsonb->'records')=50,'bounded first page');
select pg_temp.assert_true(current_setting('test.audit.first')::jsonb#>>'{records,0,id}'='9007199254741042','same-time IDs sorted without precision loss');
select pg_temp.assert_true(jsonb_typeof(current_setting('test.audit.first')::jsonb#>'{records,0,id}')='string','bigint encoded as string');
select pg_temp.assert_true((select count(*)=5 from jsonb_object_keys(current_setting('test.audit.first')::jsonb#>'{records,0}')),'only audit columns exposed');
select pg_temp.assert_true(jsonb_array_length(public.oi_operator_audit('2026-11-01Z','2026-11-02Z','evidence')->'records')=18,'evidence filter');
select pg_temp.assert_true(jsonb_array_length(public.oi_operator_audit('2026-11-01Z','2026-11-02Z','stories')->'records')=17,'story filter');
select pg_temp.assert_true(jsonb_array_length(public.oi_operator_audit('2026-11-01Z','2026-11-02Z','accounts')->'records')=17,'account filter');
-- New records before the cursor do not shift subsequent pages.
reset role;
insert into benchmark_private.oi_audit(id,actor_id,action,target_id,created_at) overriding system value
values(9007199254741043,'a1450000-0000-4000-8000-000000000001','review_story','a1450000-0000-4000-8000-000000000003','2026-11-01T02:00:00Z');
set local role authenticated;
select set_config('test.audit.last',public.oi_operator_audit('2026-11-01Z','2026-11-02Z',
  p_cursor_at=>(current_setting('test.audit.first')::jsonb#>>'{next_cursor,created_at}')::timestamptz,
  p_cursor_id=>(current_setting('test.audit.first')::jsonb#>>'{next_cursor,id}')::bigint)::text,true);
select pg_temp.assert_true(jsonb_array_length(current_setting('test.audit.last')::jsonb->'records')=2,'cursor preserves remaining rows and excludes time boundaries');
select pg_temp.assert_true(current_setting('test.audit.last')::jsonb->'next_cursor'='null'::jsonb,'last page ends');
select pg_temp.assert_true((select count(*)=0 from jsonb_array_elements(current_setting('test.audit.first')::jsonb->'records') a
  join jsonb_array_elements(current_setting('test.audit.last')::jsonb->'records') b on a->>'id'=b->>'id'),'pages do not overlap');
select pg_temp.assert_true(public.oi_operator_audit('2026-11-03Z','2026-11-04Z')='{"records":[],"next_cursor":null}'::jsonb,'empty range');
reset role;
delete from benchmark_private.oi_operators where user_id='a1450000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z')$q$,'42501');
reset role;
insert into benchmark_private.oi_operators values('a1450000-0000-4000-8000-000000000001');
update benchmark_private.oi_account_members set session_cutover=now() where auth_user_id='a1450000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.assert_error($q$select public.oi_operator_audit('2026-11-01Z','2026-11-02Z')$q$,'PT401');
rollback;

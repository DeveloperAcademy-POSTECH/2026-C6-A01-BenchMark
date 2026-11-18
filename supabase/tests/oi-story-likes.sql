\set ON_ERROR_STOP on
begin;
create function pg_temp.check_true(result boolean, description text) returns void language plpgsql as $$ begin
 if result is distinct from true then raise exception 'FAIL: %',description; end if;
end; $$;
create function pg_temp.check_error(command text, expected text) returns void language plpgsql as $$ begin
 begin execute command; exception when others then
  if sqlstate=expected then return; end if;
  raise exception 'Unexpected SQLSTATE %, expected %',sqlstate,expected;
 end; raise exception 'Expected error: %',expected;
end; $$;
select pg_temp.check_true(has_function_privilege('anon','public.oi_story_likes(uuid[])','EXECUTE')
  and has_function_privilege('authenticated','public.oi_story_likes(uuid[])','EXECUTE'),
  'public count RPC keeps anonymous and signed-in read permissions');
select pg_temp.check_true(not has_function_privilege('anon','public.oi_set_story_like(uuid,boolean)','EXECUTE')
  and has_function_privilege('authenticated','public.oi_set_story_like(uuid,boolean)','EXECUTE'),
  'like changes remain signed-in only');
select pg_temp.check_true(not has_function_privilege('anon','benchmark_private.oi_story_likeable(uuid)','EXECUTE')
  and not has_function_privilege('authenticated','benchmark_private.oi_story_likeable(uuid)','EXECUTE')
  and not has_function_privilege('service_role','benchmark_private.oi_story_likeable(uuid)','EXECUTE'),
  'visibility helper stays private after replacement');
select pg_temp.check_true(not has_table_privilege('anon','benchmark_private.oi_story_likes','SELECT')
  and not has_table_privilege('authenticated','benchmark_private.oi_story_likes','SELECT'),
  'individual like records stay private');
select pg_temp.check_true((select prosecdef and provolatile='s' from pg_proc
  where oid='benchmark_private.oi_story_likeable(uuid)'::regprocedure),
  'visibility helper retains its stable security-definer contract');
insert into auth.users(id) values
 ('50400000-0000-4000-8000-000000000001'),('50400000-0000-4000-8000-000000000002'),
 ('50400000-0000-4000-8000-000000000003');
insert into auth.sessions(id,user_id) values
 ('50400000-0000-4000-8000-000000000021','50400000-0000-4000-8000-000000000001'),
 ('50400000-0000-4000-8000-000000000022','50400000-0000-4000-8000-000000000002'),
 ('50400000-0000-4000-8000-000000000023','50400000-0000-4000-8000-000000000003');
insert into public.oi_stories(id,user_id,storage_owner_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
select ('50400000-0000-4000-8000-00000000001'||i)::uuid,'50400000-0000-4000-8000-000000000001','50400000-0000-4000-8000-000000000001',
  'pond','Synthetic story','Synthetic body','감사','기쁨','테스트오이','OiCats','MYBasicCard',36.01261057,129.31972687,
  case when i=2 then 'hidden' when i=3 then 'deleted' else 'published' end from generate_series(1,3) i;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'count'='0','anonymous reads zero');
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'liked'='false','anonymous never liked');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)$q$,'42501');
select pg_temp.check_error($q$select * from benchmark_private.oi_story_likes$q$,'42501');
select pg_temp.check_error($q$select benchmark_private.oi_story_likeable('50400000-0000-4000-8000-000000000011')$q$,'42501');
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000012','50400000-0000-4000-8000-000000000013']::uuid[])='[]'::jsonb,'anonymous cannot read hidden/deleted counts');

set local role authenticated;
select set_config('request.jwt.claim.sub','50400000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)->>'count'='1','first like counts');
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)->>'count'='1','repeat like is idempotent');
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'liked'='true','own like visible');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000012',true)$q$,'22023');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000012',false)$q$,'22023');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000013',true)$q$,'22023');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000013',false)$q$,'22023');
select pg_temp.check_error($q$select * from benchmark_private.oi_story_likes$q$,'42501');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000011',null)$q$,'22023');
select set_config('request.jwt.claim.sub','50400000-0000-4000-8000-000000000003',true);
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'liked'='false','other account is not liked');
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)->>'count'='2','second account counts');
select pg_temp.check_true(jsonb_array_length(public.oi_story_likes(array['50400000-0000-4000-8000-000000000012']::uuid[]))=0,'hidden story has no public count');
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',false)->>'count'='1','unlike removes only own like');
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',false)->>'count'='1','repeat unlike is idempotent');
select pg_temp.check_error($q$select public.oi_story_likes((select array_agg(gen_random_uuid()) from generate_series(1,201)))$q$,'22023');

-- The story remains published while deletion is prepared, but public RLS hides
-- it immediately. The definer RPCs must not reveal its known UUID or like count.
reset role;
insert into benchmark_private.oi_account_deletions(account_id)
  values('50400000-0000-4000-8000-000000000001');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(not exists(select 1 from public.oi_stories
  where id='50400000-0000-4000-8000-000000000011'), 'public story RLS hides a departing author');
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])='[]'::jsonb,
  'anonymous count lookup hides a departing author');
set local role authenticated;
select set_config('request.jwt.claim.sub','50400000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])='[]'::jsonb,
  'signed-in count lookup hides a departing author');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)$q$,'22023');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000011',false)$q$,'22023');
reset role;
delete from benchmark_private.oi_account_deletions where account_id='50400000-0000-4000-8000-000000000001';
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'count'='1',
  'cancelling deletion restores the unchanged public count');
set local role authenticated;
select set_config('request.jwt.claim.sub','50400000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'liked'='true',
  'denied changes preserve the existing account like');

reset role;
delete from public.oi_stories where id='50400000-0000-4000-8000-000000000011';
select pg_temp.check_true(not exists(select 1 from benchmark_private.oi_story_likes),'likes are removed with the story');
rollback;

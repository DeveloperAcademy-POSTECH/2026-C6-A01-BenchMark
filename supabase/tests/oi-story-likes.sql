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
  case when i=2 then 'hidden' else 'published' end from generate_series(1,2) i;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'count'='0','anonymous reads zero');
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'liked'='false','anonymous never liked');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)$q$,'42501');
select pg_temp.check_error($q$select * from benchmark_private.oi_story_likes$q$,'42501');

set local role authenticated;
select set_config('request.jwt.claim.sub','50400000-0000-4000-8000-000000000002',true);
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)->>'count'='1','first like counts');
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)->>'count'='1','repeat like is idempotent');
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'liked'='true','own like visible');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000012',true)$q$,'22023');
select pg_temp.check_error($q$select public.oi_set_story_like('50400000-0000-4000-8000-000000000011',null)$q$,'22023');
select set_config('request.jwt.claim.sub','50400000-0000-4000-8000-000000000003',true);
select pg_temp.check_true(public.oi_story_likes(array['50400000-0000-4000-8000-000000000011']::uuid[])->0->>'liked'='false','other account is not liked');
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',true)->>'count'='2','second account counts');
select pg_temp.check_true(jsonb_array_length(public.oi_story_likes(array['50400000-0000-4000-8000-000000000012']::uuid[]))=0,'hidden story has no public count');
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',false)->>'count'='1','unlike removes only own like');
select pg_temp.check_true(public.oi_set_story_like('50400000-0000-4000-8000-000000000011',false)->>'count'='1','repeat unlike is idempotent');
select pg_temp.check_error($q$select public.oi_story_likes((select array_agg(gen_random_uuid()) from generate_series(1,201)))$q$,'22023');

reset role;
delete from public.oi_stories where id='50400000-0000-4000-8000-000000000011';
select pg_temp.check_true(not exists(select 1 from benchmark_private.oi_story_likes),'likes are removed with the story');
rollback;

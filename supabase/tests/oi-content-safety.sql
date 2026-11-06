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
 ('19700000-0000-4000-8000-000000000001'),('19700000-0000-4000-8000-000000000002'),
 ('19700000-0000-4000-8000-000000000003'),('19700000-0000-4000-8000-000000000004');
insert into benchmark_private.oi_operators(user_id) values('19700000-0000-4000-8000-000000000003');
insert into public.oi_stories(id,user_id,storage_owner_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
select id::uuid,'19700000-0000-4000-8000-000000000001','19700000-0000-4000-8000-000000000001',null,'pond','Synthetic story','Synthetic content','감사','기쁨','검사 오이','OiCats','MYBlueCard',36.01261,129.31972,'published'
from (values('19700000-0000-4000-8000-000000000011'),('19700000-0000-4000-8000-000000000012')) t(id);
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_error($q$select public.oi_report_content('19700000-0000-4000-8000-000000000011','abuse','')$q$,'42501');
select pg_temp.check_error($q$select * from benchmark_private.oi_content_reports$q$,'42501');
set local role authenticated;
select set_config('request.jwt.claim.sub','19700000-0000-4000-8000-000000000002',true);
select pg_temp.check_error('select public.oi_content_reports()','42501');
select pg_temp.check_error($q$select public.oi_report_content('19700000-0000-4000-8000-000000000011',null,'')$q$,'22023');
select set_config('test.report',public.oi_report_content('19700000-0000-4000-8000-000000000011','abuse','Synthetic report')::text,true);
select pg_temp.check_true(public.oi_report_content('19700000-0000-4000-8000-000000000011','abuse','retry')->>'id'=current_setting('test.report')::jsonb->>'id','duplicate submission is idempotent');
select pg_temp.check_error($q$select public.oi_review_content((current_setting('test.report')::jsonb->>'id')::uuid,'hidden','reason')$q$,'42501');
select set_config('request.jwt.claim.sub','19700000-0000-4000-8000-000000000001',true);
select pg_temp.check_error($q$select public.oi_report_content('19700000-0000-4000-8000-000000000012','abuse','self')$q$,'42501');
select set_config('request.jwt.claim.sub','19700000-0000-4000-8000-000000000003',true);
select pg_temp.check_true(jsonb_array_length(public.oi_content_reports())=1,'operator receives private inbox');
select pg_temp.check_error($q$select public.oi_review_content((current_setting('test.report')::jsonb->>'id')::uuid,'suspended','')$q$,'22023');
select public.oi_review_content((current_setting('test.report')::jsonb->>'id')::uuid,'suspended','Synthetic moderation');
select pg_temp.check_error($q$select public.oi_review_content((current_setting('test.report')::jsonb->>'id')::uuid,'dismissed','conflict')$q$,'PT409');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true((select count(*)=0 from public.oi_stories where user_id='19700000-0000-4000-8000-000000000001'),'all restricted author stories disappear publicly');
set local role authenticated;
select set_config('request.jwt.claim.sub','19700000-0000-4000-8000-000000000002',true);
select pg_temp.check_error($q$select public.oi_mutate('collect','{"id":"19700000-0000-4000-8000-000000000012"}')$q$,'42501');
reset role;
select set_config('request.jwt.claim.sub','19700000-0000-4000-8000-000000000001',true);
select pg_temp.check_error($q$update public.oi_stories set body='changed' where id='19700000-0000-4000-8000-000000000012'$q$,'42501');
-- Mimic the trusted account merge ownership and membership updates; restriction follows the member.
select set_config('request.jwt.claim.sub','',true);
update public.oi_stories set user_id='19700000-0000-4000-8000-000000000004' where user_id='19700000-0000-4000-8000-000000000001';
update benchmark_private.oi_account_members set account_id='19700000-0000-4000-8000-000000000004' where auth_user_id='19700000-0000-4000-8000-000000000001';
select pg_temp.check_true(benchmark_private.oi_content_restricted('19700000-0000-4000-8000-000000000004'),'restriction survives account merge');
set local role authenticated;
select set_config('request.jwt.claim.sub','19700000-0000-4000-8000-000000000003',true);
select public.oi_review_content((current_setting('test.report')::jsonb->>'id')::uuid,'restore','Synthetic appeal accepted');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true((select count(*)=1 from public.oi_stories where user_id='19700000-0000-4000-8000-000000000004'),'restoration never republishes explicitly hidden story');
rollback;

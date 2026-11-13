\set ON_ERROR_STOP on
-- #291 NFC postcard tags: public lookup follows story visibility, only operators link tags.
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
 ('29100000-0000-4000-8000-000000000001'),('29100000-0000-4000-8000-000000000002'),('29100000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators(user_id) values('29100000-0000-4000-8000-000000000003');
insert into public.oi_stories(id,user_id,storage_owner_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
select id::uuid,'29100000-0000-4000-8000-000000000001','29100000-0000-4000-8000-000000000001',null,'pond','Synthetic postcard','Synthetic letter','감사','기쁨','검사 오이','OiCats','MYBlueCard',36.01261,129.31972,status
from (values('29100000-0000-4000-8000-000000000011','published'),('29100000-0000-4000-8000-000000000012','pending')) t(id,status);

-- Only operators can link tags, and the private table is never readable directly.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_error($q$select public.oi_operator_set_nfc_tag('pond-01','29100000-0000-4000-8000-000000000011',true,'')$q$,'42501');
select pg_temp.check_error($q$select * from benchmark_private.oi_nfc_tags$q$,'42501');
select pg_temp.check_true(public.oi_nfc_postcard('pond-01') is null,'unknown tag shows nothing');
set local role authenticated;
select set_config('request.jwt.claim.sub','29100000-0000-4000-8000-000000000002',true);
select pg_temp.check_error($q$select public.oi_operator_set_nfc_tag('pond-01','29100000-0000-4000-8000-000000000011',true,'')$q$,'42501');
select pg_temp.check_error('select public.oi_operator_nfc_tags()','42501');

select set_config('request.jwt.claim.sub','29100000-0000-4000-8000-000000000003',true);
select pg_temp.check_error($q$select public.oi_operator_set_nfc_tag('Pond 01','29100000-0000-4000-8000-000000000011',true,'')$q$,'22023');
select pg_temp.check_error($q$select public.oi_operator_set_nfc_tag('pond-01','29100000-0000-4000-8000-000000000099',true,'')$q$,'PT404');
select public.oi_operator_set_nfc_tag('pond-01','29100000-0000-4000-8000-000000000011',true,'Synthetic location memo');
select public.oi_operator_set_nfc_tag('pond-02','29100000-0000-4000-8000-000000000012',true,'');
select pg_temp.check_true(jsonb_array_length(public.oi_operator_nfc_tags())=2,'operator lists every tag');
select pg_temp.check_true(public.oi_operator_nfc_tags()->1->>'story_status'='pending','operator sees unpublished link');

-- Public lookup returns only active tags on published, unrestricted stories, without the memo.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_nfc_postcard('pond-01')='29100000-0000-4000-8000-000000000011','active tag opens published story');
select pg_temp.check_true(public.oi_nfc_postcard('pond-02') is null,'pending story stays hidden');

set local role authenticated;
select set_config('request.jwt.claim.sub','29100000-0000-4000-8000-000000000003',true);
select public.oi_operator_set_nfc_tag('pond-01','29100000-0000-4000-8000-000000000011',false,'Synthetic location memo');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_nfc_postcard('pond-01') is null,'retired tag shows nothing');

-- Relinking the same locked tag moves it to another story.
set local role authenticated;
select set_config('request.jwt.claim.sub','29100000-0000-4000-8000-000000000003',true);
select public.oi_operator_set_nfc_tag('pond-01','29100000-0000-4000-8000-000000000011',true,'');
reset role;
update public.oi_stories set status='published' where id='29100000-0000-4000-8000-000000000012';
set local role authenticated;
select set_config('request.jwt.claim.sub','29100000-0000-4000-8000-000000000003',true);
select public.oi_operator_set_nfc_tag('pond-01','29100000-0000-4000-8000-000000000012',true,'');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_nfc_postcard('pond-01')='29100000-0000-4000-8000-000000000012','relinked tag opens the new story');

-- Hiding or deleting the story stops the tag at once.
reset role;
update public.oi_stories set status='hidden' where id='29100000-0000-4000-8000-000000000012';
set local role anon;
select pg_temp.check_true(public.oi_nfc_postcard('pond-01') is null,'hidden story is not reachable by tag');
reset role;
delete from public.oi_stories where id='29100000-0000-4000-8000-000000000012';
select pg_temp.check_true((select story_id is null from benchmark_private.oi_nfc_tags where tag_id='pond-01'),'deleted story leaves an empty tag');
select pg_temp.check_true((select count(*)=5 from benchmark_private.oi_audit
  where actor_id='29100000-0000-4000-8000-000000000003' and action like 'nfc_tag:%'),'tag changes are audited');

-- Postcard back follows the reviewed card snapshot of a published story.
reset role;
update public.oi_stories set card_snapshot_id='29100000-0000-4000-8000-000000000031' where id='29100000-0000-4000-8000-000000000011';
insert into public.oi_stories(id,user_id,storage_owner_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status,card_snapshot_id)
values('29100000-0000-4000-8000-000000000013','29100000-0000-4000-8000-000000000001','29100000-0000-4000-8000-000000000001',null,'pond','Synthetic pending','Synthetic letter','감사','기쁨','검사 오이','OiCats','MYBlueCard',36.01261,129.31972,'pending','29100000-0000-4000-8000-000000000033');
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','29100000-0000-4000-8000-000000000001/29100000-0000-4000-8000-000000000011/card/29100000-0000-4000-8000-000000000031-back.png','{"mimetype":"image/png","size":1024}'),
 ('oi-story-media','29100000-0000-4000-8000-000000000001/29100000-0000-4000-8000-000000000011/card/29100000-0000-4000-8000-000000000032-back.png','{"mimetype":"image/png","size":1024}'),
 ('oi-story-media','29100000-0000-4000-8000-000000000001/29100000-0000-4000-8000-000000000013/card/29100000-0000-4000-8000-000000000033-back.png','{"mimetype":"image/png","size":1024}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true((select count(*)=1 from storage.objects where name like '%-back.png'),'only the approved back of a published story is public');
select pg_temp.check_true((select name like '%000000000031-back.png' from storage.objects where name like '%-back.png'),'back matches the reviewed snapshot');
set local role authenticated;
select set_config('request.jwt.claim.sub','29100000-0000-4000-8000-000000000002',true);
select pg_temp.check_true((select count(*)=1 from storage.objects where name like '%-back.png'),'other accounts cannot read pending or stale backs');

select 'PASS: NFC postcard tag roles, validation, visibility, retirement, relinking, story removal, audit and postcard back visibility; synthetic changes rolled back' as result;
rollback;

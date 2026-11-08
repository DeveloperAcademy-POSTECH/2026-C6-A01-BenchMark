\set ON_ERROR_STOP on
begin;

create function pg_temp.check_result(value boolean, message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception '%',message; end if; end;
$$;

create function pg_temp.action(action text, revision integer, fields jsonb default '{}') returns jsonb language sql as $$
  select public.oi_mutate(action,jsonb_build_object('id','c2400000-0000-4000-8000-000000000011','revision',revision)||fields);
$$;

create function pg_temp.look() returns jsonb language sql as $$
  select '{"id":"c2400000-0000-4000-8000-000000000021","top":"hoodie","bottom":"shorts",
    "topColor":16711680,"bottomColor":255,"shoeColor":65280,"topTexture":true,"bottomTexture":false}'::jsonb;
$$;

insert into auth.users(id) values
  ('c2400000-0000-4000-8000-000000000001'),('c2400000-0000-4000-8000-000000000002'),('c2400000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('c2400000-0000-4000-8000-000000000003');

set local role authenticated;
select set_config('request.jwt.claim.sub','c2400000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_capabilities()->>'public_cucumber_appearance'='true','appearance capability is present');
select pg_temp.action('save_story',0,'{"region_id":"pond","title":"Synthetic outfit","body":"Synthetic draft","theme":"감사","emotion":"기쁨",
  "cucumber_name":"테스트오이","cucumber_asset":"OiCats","card_asset":"MYBasicCard",
  "latitude":36.01261057,"longitude":129.31972687,"height_meters":1.2,"heading_degrees":42}');

-- Unattached versions, unreferenced files, and files from a different story must stay private.
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000021/portrait.png','{"mimetype":"image/png","size":1024}'),
 ('oi-story-media','c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000021/bottom.png','{"mimetype":"image/png","size":1024}'),
 ('oi-story-media','c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000022/portrait.png','{"mimetype":"image/png","size":1024}');
do $$
begin
  begin
    perform pg_temp.action('attach_media',1,jsonb_build_object('paths',jsonb_build_array(
      'c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000021/portrait.png')));
    raise exception 'Appearance cannot be attached as an ordinary photo';
  exception when invalid_parameter_value then null; end;
  begin
    perform pg_temp.action('submit_story',1,jsonb_build_object('cucumber_appearance',pg_temp.look()));
    raise exception 'An incomplete appearance was accepted';
  exception when invalid_parameter_value then null; end;
end;
$$;
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media','c2400000-0000-4000-8000-000000000001/c2400000-0000-4000-8000-000000000011/appearance/c2400000-0000-4000-8000-000000000021/top.png','{"mimetype":"image/png","size":1024}');
do $$
begin
  begin
    perform pg_temp.action('submit_story',1,jsonb_build_object('cucumber_appearance',pg_temp.look()||'{"originalPhoto":"private"}'));
    raise exception 'Unexpected raw photo field was accepted';
  exception when invalid_parameter_value then null; end;
end;
$$;
select pg_temp.check_result((pg_temp.action('submit_story',1,jsonb_build_object('cucumber_appearance',pg_temp.look()))->>'status')='pending','snapshot is submitted atomically');
select pg_temp.check_result((select count(*) from storage.objects where bucket_id='oi-story-media' and name like 'c240%')=2,'writer can preview the submitted images only');

select set_config('request.jwt.claim.sub','c2400000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(not exists(select 1 from public.oi_stories where id='c2400000-0000-4000-8000-000000000011'),'another account cannot see the pending snapshot');
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c240%'),'another account cannot see its files');

set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c240%'),'anonymous read is denied before approval');

set local role authenticated;
select set_config('request.jwt.claim.sub','c2400000-0000-4000-8000-000000000003',true);
select pg_temp.check_result(exists(select 1 from storage.objects where name like 'c240%/top.png'),'operator can review the applied photo atlas');
do $$
begin
  begin
    perform pg_temp.action('review_story',2,'{"status":"published"}');
    raise exception 'An operator using an old app approved an unreviewed appearance';
  exception when serialization_failure then null; end;
  begin
    perform pg_temp.action('review_story',1,'{"status":"published","appearance_id":"c2400000-0000-4000-8000-000000000021"}');
    raise exception 'An operator approved a stale story revision';
  exception when serialization_failure then null; end;
end;
$$;
select pg_temp.action('review_story',2,'{"status":"published","appearance_id":"c2400000-0000-4000-8000-000000000021"}');

set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result((select cucumber_appearance=pg_temp.look() and status='published' and height_meters=1.2 and heading_degrees=42
  from public.oi_stories where id='c2400000-0000-4000-8000-000000000011'),'approved clothes and colors match the submission and geometry is preserved');
select pg_temp.check_result((select count(*) from storage.objects where name like 'c240%')=2,'public can read only the approved portrait and applied atlas');

set local role authenticated;
select set_config('request.jwt.claim.sub','c2400000-0000-4000-8000-000000000003',true);
select pg_temp.action('review_story',3,'{"status":"hidden"}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c240%'),'new anonymous image requests are denied after hiding');
rollback;

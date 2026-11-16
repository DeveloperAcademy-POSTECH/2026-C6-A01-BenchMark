\set ON_ERROR_STOP on
begin;
-- Synthetic accounts and Storage metadata only; all fixtures are rolled back.
create function pg_temp.check_result(value boolean,message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.action(action text,revision integer,fields jsonb default '{}') returns jsonb language sql as $$
  select public.oi_mutate(action,jsonb_build_object('id','c3310000-0000-4000-8000-000000000011','revision',revision)||fields);
$$;
create function pg_temp.paths(format integer default 3) returns text[] language sql as $$
  select benchmark_private.oi_story_card_parts('c3310000-0000-4000-8000-000000000001',
    'c3310000-0000-4000-8000-000000000011','c3310000-0000-4000-8000-000000000031',format);
$$;
create function pg_temp.reject_submission(message text,format integer default 3) returns void language plpgsql as $$
begin
  begin
    perform pg_temp.action('submit_story',1,jsonb_build_object(
      'card_snapshot_id','c3310000-0000-4000-8000-000000000031','card_snapshot_format',format));
    raise exception '%',message;
  exception when invalid_parameter_value then null; end;
  perform pg_temp.check_result((select status='draft' and revision=1 and card_snapshot_id is null and card_snapshot_format=1
    from public.oi_stories where id='c3310000-0000-4000-8000-000000000011'),'invalid submission is atomic');
end; $$;
select pg_temp.check_result(pg_temp.paths(1)=array[
 'c3310000-0000-4000-8000-000000000001/c3310000-0000-4000-8000-000000000011/card/c3310000-0000-4000-8000-000000000031.png'
 ],'legacy single front path is unchanged');
select pg_temp.check_result(pg_temp.paths(2)=pg_temp.paths(1)||array[
 'c3310000-0000-4000-8000-000000000001/c3310000-0000-4000-8000-000000000011/card/c3310000-0000-4000-8000-000000000031/back.png',
 'c3310000-0000-4000-8000-000000000001/c3310000-0000-4000-8000-000000000011/card/c3310000-0000-4000-8000-000000000031/front-preview.png',
 'c3310000-0000-4000-8000-000000000001/c3310000-0000-4000-8000-000000000011/card/c3310000-0000-4000-8000-000000000031/back-preview.png'
 ],'duplex paths and order are unchanged');
select pg_temp.check_result(pg_temp.paths(3)=pg_temp.paths(2)||array[
 'c3310000-0000-4000-8000-000000000001/c3310000-0000-4000-8000-000000000011/card/c3310000-0000-4000-8000-000000000031/cover.png'
 ],'format 3 adds exactly one cover');
insert into auth.users(id) values
 ('c3310000-0000-4000-8000-000000000001'),('c3310000-0000-4000-8000-000000000002'),('c3310000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('c3310000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3310000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_capabilities() @> '{"story_card_cover":true,"duplex_story_card":true,"public_story_card":true}',
 'new and existing card capabilities are advertised to the submitting client');
select pg_temp.action('save_story',0,'{"region_id":"pond","title":"Synthetic cover","body":"Synthetic postcard","theme":"감사","emotion":"기쁨",
 "cucumber_name":"테스트오이","cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057,"longitude":129.31972687}');
insert into storage.objects(bucket_id,name,metadata)
 select 'oi-story-media',path,'{"mimetype":"image/png","size":2048}'::jsonb from unnest(pg_temp.paths(2)) path;
select pg_temp.reject_submission('Missing cover was submitted');
select pg_temp.reject_submission('Unknown format was submitted',4);
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media',(pg_temp.paths())[5],'{"mimetype":"image/jpeg","size":2048}');
select pg_temp.reject_submission('A JPEG cover was submitted');
reset role;
update storage.objects set metadata='{"mimetype":"image/png","size":8388609}' where name=(pg_temp.paths())[5];
set local role authenticated;
select pg_temp.reject_submission('An oversized cover was submitted');
reset role;
update storage.objects set metadata='{"mimetype":"image/png","size":0}' where name=(pg_temp.paths())[5];
set local role authenticated;
select pg_temp.reject_submission('An empty cover was submitted');
reset role;
update storage.objects set metadata='{"mimetype":"image/png","size":8388608}' where name=(pg_temp.paths())[5];
do $$ begin
  begin
    update public.oi_stories set card_snapshot_format=3 where id='c3310000-0000-4000-8000-000000000011';
    raise exception 'Format 3 without snapshot was accepted';
  exception when check_violation then null; end;
  begin
    update public.oi_stories set card_snapshot_format=4 where id='c3310000-0000-4000-8000-000000000011';
    raise exception 'Unknown format bypassed the table constraint';
  exception when check_violation then null; end;
end; $$;
set local role authenticated;
select pg_temp.check_result((select count(*) from storage.objects where name=any(pg_temp.paths()))=5,'writer can read all staged files');
-- A stale cover with the right story but a different snapshot must never become public.
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media',replace((pg_temp.paths())[5],'000000000031/cover','000000000032/cover'),'{"mimetype":"image/png","size":2048}');
select set_config('request.jwt.claim.sub','c3310000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c331%'),'other writer cannot read draft files');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c331%'),'anon cannot read draft files');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3310000-0000-4000-8000-000000000001',true);
select pg_temp.action('submit_story',1,'{"card_snapshot_id":"c3310000-0000-4000-8000-000000000031","card_snapshot_format":3}');
select pg_temp.check_result((select card_snapshot_format=3 and revision=2 and status='pending'
 from public.oi_stories where id='c3310000-0000-4000-8000-000000000011'),'five files bind to one pending revision');
select pg_temp.check_result((select count(*) from storage.objects where name=any(pg_temp.paths()))=5,'writer can read pending bundle');
select set_config('request.jwt.claim.sub','c3310000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c331%'),'other writer cannot read pending files');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c331%'),'anon cannot read pending files');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3310000-0000-4000-8000-000000000003',true);
select pg_temp.check_result((select count(*) from storage.objects where name=any(pg_temp.paths()))=5,'operator can review the cover too');
do $$ declare fields jsonb; begin
  for fields in select value from jsonb_array_elements('[{}, {"card_snapshot_format":1}, {"card_snapshot_format":2}, {"card_snapshot_format":4},
    {"card_snapshot_format":3,"card_snapshot_id":"c3310000-0000-4000-8000-000000000032"}]') loop
    begin
      perform pg_temp.action('review_story',2,'{"status":"published","card_snapshot_id":"c3310000-0000-4000-8000-000000000031"}'::jsonb||fields);
      raise exception 'An operator approved a different or downgraded card: %',fields;
    exception when serialization_failure then null; end;
  end loop;
end; $$;
-- Approval rechecks the cover, even if Storage metadata changes after submission.
reset role;
update storage.objects set metadata='{"mimetype":"image/jpeg","size":2048}' where name=(pg_temp.paths())[5];
set local role authenticated;
do $$ begin
  begin
    perform pg_temp.action('review_story',2,'{"status":"published","card_snapshot_id":"c3310000-0000-4000-8000-000000000031","card_snapshot_format":3}');
    raise exception 'An invalid cover was approved';
  exception when invalid_parameter_value then null; end;
end; $$;
reset role;
update storage.objects set metadata='{"mimetype":"image/png","size":2048}' where name=(pg_temp.paths())[5];
set local role authenticated;
select pg_temp.action('review_story',2,'{"status":"published","card_snapshot_id":"c3310000-0000-4000-8000-000000000031","card_snapshot_format":3}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result((select count(*) from storage.objects where name like 'c331%')=5,'only current five files become public');
select pg_temp.check_result(exists(select 1 from storage.objects where name=(pg_temp.paths())[5]),'anon can read the published cover');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3310000-0000-4000-8000-000000000001',true);
select pg_temp.action('reopen_story',3);
select pg_temp.action('submit_story',4);
select pg_temp.check_result((select card_snapshot_format=3 and revision=5 and status='pending'
 from public.oi_stories where id='c3310000-0000-4000-8000-000000000011'),'resubmit without new snapshot preserves the format');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c331%'),'reopened/resubmitted bundle is private again');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3310000-0000-4000-8000-000000000001',true);
select pg_temp.action('delete_story',5);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c331%'),'writer cannot read deleted story files');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c331%'),'deleted cover stays private');
rollback;

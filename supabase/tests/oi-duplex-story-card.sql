\set ON_ERROR_STOP on
begin;
create function pg_temp.check_result(value boolean,message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.action(action text,revision integer,fields jsonb default '{}') returns jsonb language sql as $$
  select public.oi_mutate(action,jsonb_build_object('id','c3080000-0000-4000-8000-000000000011','revision',revision)||fields);
$$;
create function pg_temp.paths() returns text[] language sql as $$
  select benchmark_private.oi_story_card_parts('c3080000-0000-4000-8000-000000000001',
    'c3080000-0000-4000-8000-000000000011','c3080000-0000-4000-8000-000000000031',2);
$$;
insert into auth.users(id) values
 ('c3080000-0000-4000-8000-000000000001'),('c3080000-0000-4000-8000-000000000002'),('c3080000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('c3080000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3080000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_capabilities()->>'duplex_story_card'='true','duplex capability is advertised');
select pg_temp.action('save_story',0,'{"region_id":"pond","title":"Synthetic duplex","body":"Synthetic postcard","theme":"감사","emotion":"기쁨",
 "cucumber_name":"테스트오이","cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057,"longitude":129.31972687}');
insert into storage.objects(bucket_id,name,metadata)
 select 'oi-story-media',path,'{"mimetype":"image/png","size":2048}'::jsonb from unnest((pg_temp.paths())[1:3]) path;
do $$ begin
  begin
    perform pg_temp.action('submit_story',1,'{"card_snapshot_id":"c3080000-0000-4000-8000-000000000031","card_snapshot_format":2}');
    raise exception 'Partial upload was submitted';
  exception when invalid_parameter_value then null; end;
end; $$;
select pg_temp.check_result((select status='draft' and card_snapshot_id is null and card_snapshot_format=1
 from public.oi_stories where id='c3080000-0000-4000-8000-000000000011'),'partial bundle leaves the story unchanged');
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media',(pg_temp.paths())[4],'{"mimetype":"image/png","size":2048}'),
 ('oi-story-media','c3080000-0000-4000-8000-000000000001/c3080000-0000-4000-8000-000000000011/card/c3080000-0000-4000-8000-000000000031-back.png','{"mimetype":"image/png","size":2048}');
select pg_temp.action('submit_story',1,'{"card_snapshot_id":"c3080000-0000-4000-8000-000000000031","card_snapshot_format":2}');
select pg_temp.check_result((select card_snapshot_format=2 and revision=2 and status='pending'
 from public.oi_stories where id='c3080000-0000-4000-8000-000000000011'),'all files bind to one pending revision');
select set_config('request.jwt.claim.sub','c3080000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c308%'),'another writer cannot read the pending bundle');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c308%'),'App Clip cannot read unapproved files');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3080000-0000-4000-8000-000000000003',true);
select pg_temp.check_result((select count(*) from storage.objects where name=any(pg_temp.paths()))=4,'operator sees every submitted image');
do $$ begin
  begin
    perform pg_temp.action('review_story',2,'{"status":"published","card_snapshot_id":"c3080000-0000-4000-8000-000000000031"}');
    raise exception 'A legacy operator approved a duplex card';
  exception when serialization_failure then null; end;
end; $$;
select pg_temp.action('review_story',2,'{"status":"published","card_snapshot_id":"c3080000-0000-4000-8000-000000000031","card_snapshot_format":2}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result((select count(*) from storage.objects where name like 'c308%')=4,'only the four approved files become public');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3080000-0000-4000-8000-000000000003',true);
select pg_temp.action('review_story',3,'{"status":"hidden"}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c308%'),'hiding blocks new image and signed URL requests');
rollback;

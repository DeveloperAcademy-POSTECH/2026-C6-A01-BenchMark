\set ON_ERROR_STOP on
begin;
-- Synthetic accounts and metadata only. No hosted Storage or production DB.
create function pg_temp.check_result(value boolean,message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception '%',message; end if; end; $$;
create function pg_temp.action(action text,revision integer,fields jsonb default '{}') returns jsonb language sql as $$
  select public.oi_mutate(action,jsonb_build_object('id','c3480000-0000-4000-8000-000000000011','revision',revision)||fields);
$$;
create function pg_temp.paths(kind text default 'jpeg',snapshot uuid default 'c3480000-0000-4000-8000-000000000031')
returns text[] language sql as $$
  select benchmark_private.oi_story_card_parts('c3480000-0000-4000-8000-000000000001',
    'c3480000-0000-4000-8000-000000000011',snapshot,3,kind);
$$;
create function pg_temp.reject_submission(fields jsonb,message text,expected_revision integer default 1)
returns void language plpgsql as $$
declare before_row jsonb;
begin
  select to_jsonb(s) into before_row from public.oi_stories s where id='c3480000-0000-4000-8000-000000000011';
  begin
    perform pg_temp.action('submit_story',expected_revision,fields);
    raise exception '%',message;
  exception when invalid_parameter_value then null; end;
  perform pg_temp.check_result((select to_jsonb(s)=before_row from public.oi_stories s
    where id='c3480000-0000-4000-8000-000000000011'),'failed submission preserves the entire story row');
end; $$;
create function pg_temp.reject_review(fields jsonb,message text) returns void language plpgsql as $$
begin
  begin
    perform pg_temp.action('review_story',2,'{"status":"published","card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3}'::jsonb||fields);
    raise exception '%',message;
  exception when serialization_failure then null; end;
  perform pg_temp.check_result((select status='pending' and revision=2 and card_cover_type='jpeg'
    from public.oi_stories where id='c3480000-0000-4000-8000-000000000011'),'failed review preserves pending JPEG');
end; $$;

select pg_temp.check_result((pg_temp.paths())[1:4]=(pg_temp.paths('png'))[1:4], 'JPEG keeps all four PNG paths and their order');
select pg_temp.check_result((pg_temp.paths())[5] like '%/cover.jpg', 'JPEG uses exactly cover.jpg');
select pg_temp.check_result(pg_temp.paths('png')=benchmark_private.oi_story_card_parts(
  'c3480000-0000-4000-8000-000000000001','c3480000-0000-4000-8000-000000000011','c3480000-0000-4000-8000-000000000031',3),
  'four-argument format 3 helper keeps the PNG contract');
select pg_temp.check_result(benchmark_private.oi_story_card_parts(
  'c3480000-0000-4000-8000-000000000001','c3480000-0000-4000-8000-000000000011','c3480000-0000-4000-8000-000000000031',2,null)
  =(pg_temp.paths())[1:4], 'NULL type does not suppress the four format-2 PNGs');
select pg_temp.check_result(pg_temp.paths(null) is null and pg_temp.paths('gif') is null, 'invalid format-3 types fail closed');
select pg_temp.check_result(not has_function_privilege('anon','benchmark_private.oi_check_story_card(public.oi_stories)','execute')
  and not has_function_privilege('authenticated','benchmark_private.oi_check_story_card(public.oi_stories)','execute'), 'validator stays private');

insert into auth.users(id) values
 ('c3480000-0000-4000-8000-000000000001'),('c3480000-0000-4000-8000-000000000002'),('c3480000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('c3480000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3480000-0000-4000-8000-000000000001',true);
select pg_temp.check_result(public.oi_capabilities() @> '{"story_card_cover_jpeg":true,"story_card_cover":true,"duplex_story_card":true,"public_story_card":true}', 'new and legacy capabilities coexist');
select pg_temp.action('save_story',0,'{"region_id":"pond","title":"Synthetic JPEG cover","body":"Synthetic postcard","theme":"감사","emotion":"기쁨",
 "cucumber_name":"테스트오이","cucumber_asset":"OiCats","card_asset":"MYBasicCard","latitude":36.01261057,"longitude":129.31972687}');
reset role;
do $$ declare sample jsonb; begin
  for sample in select value from jsonb_array_elements('[{"format":3,"type":null,"snapshot":true},
    {"format":3,"type":"gif","snapshot":true},{"format":2,"type":"jpeg","snapshot":true},
    {"format":1,"type":"png","snapshot":true},{"format":3,"type":"jpeg","snapshot":false}]') loop
    begin
      update public.oi_stories set card_snapshot_format=(sample->>'format')::integer,
        card_cover_type=sample->>'type',card_snapshot_id=case when (sample->>'snapshot')::boolean then 'c3480000-0000-4000-8000-000000000031'::uuid end
        where id='c3480000-0000-4000-8000-000000000011';
      raise exception 'invalid format/type/snapshot bypassed table constraints: %',sample;
    exception when check_violation then null; end;
  end loop;
end; $$;
set local role authenticated;
insert into storage.objects(bucket_id,name,metadata)
 select 'oi-story-media',path,'{"mimetype":"image/png","size":2048}'::jsonb from unnest((pg_temp.paths())[1:4]) path;
select pg_temp.reject_submission('{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"jpeg"}', 'missing JPEG was submitted');
-- A PNG at the old path must never satisfy a JPEG declaration.
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media',(pg_temp.paths('png'))[5],'{"mimetype":"image/png","size":8388608}');
select pg_temp.reject_submission('{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"jpeg"}', 'PNG path satisfied missing JPEG');
insert into storage.objects(bucket_id,name,metadata) values
 ('oi-story-media',(pg_temp.paths())[5],'{"mimetype":"image/png","size":2048}');
select pg_temp.reject_submission('{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"jpeg"}', 'PNG MIME passed for JPEG');
reset role;
do $$ declare sample_metadata jsonb; begin
  for sample_metadata in select value from jsonb_array_elements('[{"mimetype":"image/jpeg","size":2097153},{"mimetype":"image/jpeg","size":0},
    {"mimetype":"image/jpeg"},{"mimetype":"image/jpeg","size":-1},{"mimetype":"image/jpeg","size":"NaN"},
    {"mimetype":"image/jpeg","size":"9999999999999999999999"},{"mimetype":"image/jpeg","size":0.5},
    {"mimetype":"image/jpg","size":2048},{"size":2048}]') loop
    update storage.objects set metadata=sample_metadata where name=(pg_temp.paths())[5];
    set local role authenticated;
    perform pg_temp.reject_submission('{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"jpeg"}', 'invalid JPEG metadata passed');
    reset role;
  end loop;
end; $$;
update storage.objects set metadata='{"mimetype":"image/jpeg","size":2097152}' where name=(pg_temp.paths())[5];
set local role authenticated;
do $$ declare fields jsonb; begin
  for fields in select value from jsonb_array_elements('[{"card_cover_type":null},{"card_cover_type":"gif"},{"card_cover_type":true},
    {"card_snapshot_format":2,"card_cover_type":"jpeg"},{"card_snapshot_format":4,"card_cover_type":"jpeg"}]') loop
    perform pg_temp.reject_submission('{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3}'::jsonb||fields, 'invalid type/format combination passed');
  end loop;
end; $$;
reset role;
-- JPEG support must not permit JPEG in a PNG card part.
do $$ declare path text; begin
  foreach path in array (pg_temp.paths())[1:4] loop
    update storage.objects set metadata='{"mimetype":"image/jpeg","size":2048}' where name=path;
    set local role authenticated;
    perform pg_temp.reject_submission('{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"jpeg"}', 'JPEG was accepted in a PNG part');
    reset role;
    update storage.objects set metadata='{"mimetype":"image/png","size":2048}' where name=path;
  end loop;
end; $$;
update storage.objects set metadata='{"mimetype":"image/png","size":8388608}' where name=(pg_temp.paths())[1];
set local role authenticated;
select pg_temp.action('submit_story',1,'{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"jpeg"}');
select pg_temp.check_result((select card_snapshot_format=3 and card_cover_type='jpeg' and revision=2 and status='pending'
 from public.oi_stories where id='c3480000-0000-4000-8000-000000000011'),'2MiB JPEG and 8MiB PNG bind to the same pending revision');
select pg_temp.check_result((select count(*) from storage.objects where name like 'c348%')=5,'pending writer reads only the declared current five files');
select set_config('request.jwt.claim.sub','c3480000-0000-4000-8000-000000000002',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c348%'),'other writer cannot read pending JPEG');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c348%'),'anon cannot read pending JPEG');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3480000-0000-4000-8000-000000000003',true);
select pg_temp.check_result(exists(select 1 from storage.objects where name=(pg_temp.paths())[5]),'operator can inspect JPEG');
select pg_temp.reject_review('{}','1.2.0 operator approved JPEG without type acknowledgement');
select pg_temp.reject_review('{"card_cover_type":null}','null acknowledgement approved JPEG');
select pg_temp.reject_review('{"card_cover_type":"png"}','PNG acknowledgement approved JPEG');
select pg_temp.reject_review('{"card_cover_type":true}','non-string acknowledgement approved JPEG');
select pg_temp.reject_review('{"card_cover_type":"jpeg","card_snapshot_format":2}','format downgrade approved JPEG');
select pg_temp.reject_review('{"card_cover_type":"jpeg","card_snapshot_id":"c3480000-0000-4000-8000-000000000032"}','stale snapshot approved JPEG');
reset role;
update storage.objects set metadata='{"mimetype":"image/jpeg","size":2097153}' where name=(pg_temp.paths())[5];
set local role authenticated;
do $$ begin
  begin
    perform pg_temp.action('review_story',2,'{"status":"published","card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"jpeg"}');
    raise exception 'approval did not recheck JPEG';
  exception when invalid_parameter_value then null; end;
end; $$;
reset role;
update storage.objects set metadata='{"mimetype":"image/jpeg","size":1}' where name=(pg_temp.paths())[5];
set local role authenticated;
select pg_temp.action('review_story',2,'{"status":"published","card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"jpeg"}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result((select count(*) from storage.objects where name like 'c348%')=5,'anon reads exactly five approved current files');
select pg_temp.check_result(exists(select 1 from storage.objects where name=(pg_temp.paths())[5])
  and not exists(select 1 from storage.objects where name=(pg_temp.paths('png'))[5]),'JPEG is public and undeclared same-snapshot PNG is not');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3480000-0000-4000-8000-000000000003',true);
-- Hiding must remain available to a legacy operator without card type fields.
select pg_temp.action('review_story',3,'{"status":"hidden"}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c348%'),'hiding revokes JPEG public access');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3480000-0000-4000-8000-000000000001',true);
select pg_temp.action('reopen_story',4);
select pg_temp.reject_submission('{"card_cover_type":"png"}','type changed without a new snapshot',5);
select pg_temp.reject_submission('{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3,"card_cover_type":"png"}', 'same snapshot changed encoding',5);
select pg_temp.action('submit_story',5);
select pg_temp.check_result((select card_cover_type='jpeg' and card_snapshot_format=3 and revision=6
 from public.oi_stories where id='c3480000-0000-4000-8000-000000000011'),'omitted snapshot and type preserve JPEG on resubmission');
select pg_temp.action('reopen_story',6);
select pg_temp.action('submit_story',7,'{"card_snapshot_id":"c3480000-0000-4000-8000-000000000031","card_snapshot_format":3}');
select pg_temp.check_result((select card_cover_type='jpeg' and revision=8 from public.oi_stories
 where id='c3480000-0000-4000-8000-000000000011'),'explicit same snapshot with omitted type also preserves JPEG');
select pg_temp.action('reopen_story',8);
-- A new PNG version produced by 1.2.0 still submits and approves without type fields.
insert into storage.objects(bucket_id,name,metadata)
 select 'oi-story-media',path,'{"mimetype":"image/png","size":8388608}'::jsonb
 from unnest(pg_temp.paths('png','c3480000-0000-4000-8000-000000000032')) path;
select pg_temp.action('submit_story',9,'{"card_snapshot_id":"c3480000-0000-4000-8000-000000000032","card_snapshot_format":3}');
select pg_temp.check_result((select card_cover_type='png' and revision=10 from public.oi_stories
 where id='c3480000-0000-4000-8000-000000000011'),'new legacy snapshot defaults to PNG');
select set_config('request.jwt.claim.sub','c3480000-0000-4000-8000-000000000003',true);
select pg_temp.action('review_story',10,'{"status":"published","card_snapshot_id":"c3480000-0000-4000-8000-000000000032","card_snapshot_format":3}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name=(pg_temp.paths())[5])
  and exists(select 1 from storage.objects where name=(pg_temp.paths('png','c3480000-0000-4000-8000-000000000032'))[5]),'only the newly approved PNG version stays public');
set local role authenticated;
select set_config('request.jwt.claim.sub','c3480000-0000-4000-8000-000000000001',true);
select pg_temp.action('delete_story',11);
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_result(not exists(select 1 from storage.objects where name like 'c348%'),'deleted story exposes neither encoding');
rollback;

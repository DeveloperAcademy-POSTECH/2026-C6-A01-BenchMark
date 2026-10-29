begin;

create function pg_temp.assert_true(result boolean, description text) returns void
language plpgsql as $$ begin
  if result is distinct from true then raise exception 'FAIL: %',description; end if;
end; $$;
create function pg_temp.assert_error(command text, expected_state text) returns void
language plpgsql as $$ begin
  begin execute command;
  exception when others then
    if sqlstate=expected_state then return; end if;
    raise exception 'Unexpected SQLSTATE %, expected %, command %',sqlstate,expected_state,command;
  end;
  raise exception 'Expected error % for %',expected_state,command;
end; $$;

insert into auth.users(id) values
  ('b1000000-0000-4000-8000-000000000001'),
  ('b1000000-0000-4000-8000-000000000002'),
  ('b1000000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('b1000000-0000-4000-8000-000000000003');

set local role anon;
select pg_temp.assert_true((select count(*)=0 from public.oi_stories),'no fixture stories');
select pg_temp.assert_true((select count(*)=0 from public.oi_profiles),'unpublished profiles private');
select pg_temp.assert_error('select * from public.oi_evidence_requests','42501');
select pg_temp.assert_error($command$select public.oi_mutate('start_evidence','{"id":"b1000000-0000-4000-8000-000000000010"}')$command$,'42501');

set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((public.oi_capabilities()->>'operator')::boolean=false,'not operator by default');
select pg_temp.assert_true((public.oi_capabilities()->>'coins_enabled')::boolean=false,'coins disabled');
select pg_temp.assert_error('insert into benchmark_private.oi_operators values (auth.uid())','42501');
select pg_temp.assert_error('update public.oi_profiles set id=gen_random_uuid() where id=auth.uid()','42501');
select public.oi_mutate('start_evidence','{"id":"b1000000-0000-4000-8000-000000000010"}');
select public.oi_mutate('start_evidence','{"id":"b1000000-0000-4000-8000-000000000010"}');
select pg_temp.assert_true((select count(*)=1 from public.oi_evidence_requests),'idempotent request');
select pg_temp.assert_error($command$select public.oi_mutate('review_evidence','{"id":"b1000000-0000-4000-8000-000000000010","status":"approved","story_limit":1}')$command$,'42501');
select pg_temp.assert_error($command$select public.oi_mutate('submit_evidence','{"id":"b1000000-0000-4000-8000-000000000010","object_path":"missing"}')$command$,'22023');
insert into storage.objects(bucket_id,name) values('oi-evidence','b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000010/test.png');
select public.oi_mutate('submit_evidence','{"id":"b1000000-0000-4000-8000-000000000010","object_path":"b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000010/test.png"}');
select pg_temp.assert_error($command$insert into storage.objects(bucket_id,name) values('oi-evidence','b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000010/overwrite.png')$command$,'42501');

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.oi_evidence_requests),'other evidence hidden');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='oi-evidence'),'other evidence file hidden');
select pg_temp.assert_error($command$select public.oi_mutate('start_evidence','{"id":"b1000000-0000-4000-8000-000000000010"}')$command$,'42501');

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((public.oi_capabilities()->>'operator')::boolean,'operator capability');
select public.oi_mutate('review_evidence','{"id":"b1000000-0000-4000-8000-000000000010","status":"approved","story_limit":1,"review_note":"Synthetic test only"}');
select pg_temp.assert_error($command$select public.oi_mutate('review_evidence','{"id":"b1000000-0000-4000-8000-000000000010","status":"approved","story_limit":1}')$command$,'40001');

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
select public.oi_mutate('save_story',jsonb_build_object(
  'id','b1000000-0000-4000-8000-000000000020','grant_id',(select id from public.oi_writing_grants),
  'revision',0,'region_id','pond','title','Synthetic test story','body','Synthetic test body',
  'theme','감사','emotion','기쁨','cucumber_name','테스트오이','cucumber_asset','OiCats','card_asset','MYBlueCard',
  'latitude',36.01261057021347,'longitude',129.3197268697784));
select pg_temp.assert_error($command$select public.oi_mutate('save_story',jsonb_build_object('id','b1000000-0000-4000-8000-000000000021','grant_id',(select id from public.oi_writing_grants),'revision',0))$command$,'42501');
select pg_temp.assert_error($command$select public.oi_mutate('save_story',jsonb_build_object('id','b1000000-0000-4000-8000-000000000020','grant_id',(select id from public.oi_writing_grants),'revision',1,'latitude',0,'longitude',0))$command$,'22023');
select pg_temp.assert_error($command$select public.oi_mutate('submit_story','{"id":"b1000000-0000-4000-8000-000000000020","revision":0}')$command$,'40001');
insert into storage.objects(bucket_id,name) values('oi-story-media','b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000020/test.png');
select public.oi_mutate('attach_media','{"id":"b1000000-0000-4000-8000-000000000020","revision":1,"paths":["b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000020/test.png"]}');
select public.oi_mutate('submit_story','{"id":"b1000000-0000-4000-8000-000000000020","revision":2}');

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.oi_stories),'pending story hidden from others');
select pg_temp.assert_error($command$select public.oi_mutate('collect','{"id":"b1000000-0000-4000-8000-000000000020"}')$command$,'42501');
select pg_temp.assert_error($command$select public.oi_mutate('delete_story','{"id":"b1000000-0000-4000-8000-000000000020","revision":3}')$command$,'42501');

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000003',true);
select public.oi_mutate('review_story','{"id":"b1000000-0000-4000-8000-000000000020","revision":3,"status":"published"}');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.assert_true((select count(*)=1 from public.oi_stories),'published story readable');
select pg_temp.assert_true((select count(*)=1 from public.oi_story_media),'published media metadata readable');
select pg_temp.assert_true((select count(*)=1 from storage.objects),'only published story object readable');
select pg_temp.assert_true((select count(*)=1 from public.oi_profiles),'only published author profile readable');

set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
select public.oi_mutate('collect','{"id":"b1000000-0000-4000-8000-000000000020"}');
select public.oi_mutate('collect','{"id":"b1000000-0000-4000-8000-000000000020"}');
select pg_temp.assert_true((select count(*)=1 from public.oi_collections),'duplicate collection prevented');
select pg_temp.assert_true((select collection_count=1 from public.oi_collection_metrics() where story_id='b1000000-0000-4000-8000-000000000020'),'actual public collection count');
select public.oi_mutate('favorite','{"id":"b1000000-0000-4000-8000-000000000020","enabled":true}');
select public.oi_mutate('favorite','{"id":"b1000000-0000-4000-8000-000000000020","enabled":true}');
select pg_temp.assert_true((select count(*)=1 from public.oi_favorites),'idempotent favorite');
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true((select count(*)=0 from public.oi_collections),'other account collections hidden');
select pg_temp.assert_true((select count(*)=0 from public.oi_favorites),'other account favorites hidden');

select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000003',true);
select public.oi_mutate('review_evidence','{"id":"b1000000-0000-4000-8000-000000000010","status":"revoked","review_note":"Synthetic revocation"}');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select pg_temp.assert_true((select count(*)=0 from public.oi_stories),'revocation hides published story');
select pg_temp.assert_true((select count(*)=0 from storage.objects),'revocation hides media');
select pg_temp.assert_true((select count(*)=0 from public.oi_collection_metrics()),'hidden story has no public count');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
select public.oi_mutate('start_evidence','{"id":"b1000000-0000-4000-8000-000000000011"}');
insert into storage.objects(bucket_id,name) values('oi-evidence','b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000011/first.png');
select public.oi_mutate('submit_evidence','{"id":"b1000000-0000-4000-8000-000000000011","object_path":"b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000011/first.png"}');
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000003',true);
select public.oi_mutate('review_evidence','{"id":"b1000000-0000-4000-8000-000000000011","status":"changes_requested","review_note":"Synthetic correction request"}');
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.oi_evidence_history),'other evidence history hidden');
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
select public.oi_mutate('reopen_evidence','{"id":"b1000000-0000-4000-8000-000000000011","operation_id":"b1000000-0000-4000-8000-000000000031","expected_status":"changes_requested","expected_object_path":"b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000011/first.png"}');
select public.oi_mutate('reopen_evidence','{"id":"b1000000-0000-4000-8000-000000000011","operation_id":"b1000000-0000-4000-8000-000000000031","expected_status":"changes_requested","expected_object_path":"b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000011/first.png"}');
select pg_temp.assert_error($command$select public.oi_mutate('reopen_evidence','{"id":"b1000000-0000-4000-8000-000000000011","operation_id":"b1000000-0000-4000-8000-000000000032","expected_status":"changes_requested"}')$command$,'40001');
select pg_temp.assert_true((select count(*)=1 from public.oi_evidence_history where review_note='Synthetic correction request'),'review context retained');
insert into storage.objects(bucket_id,name) values('oi-evidence','b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000011/second.png');
select public.oi_mutate('submit_evidence','{"id":"b1000000-0000-4000-8000-000000000011","object_path":"b1000000-0000-4000-8000-000000000001/b1000000-0000-4000-8000-000000000011/second.png"}');
select pg_temp.assert_true((select count(*)=2 from public.oi_evidence_requests),'resubmission reuses original application');
reset role;
select 'PASS: approval, owner isolation, private storage, optimistic revisions, publication, idempotency, favorites, revocation, resubmission history' as result;
rollback;

-- Synthetic old uploads, including a draft an older client could have retried.
begin;
insert into auth.users(id) values
 ('d2580000-0000-4000-8000-000000000001'),
 ('d2580000-0000-4000-8000-000000000002'),
 ('d2580000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values ('d2580000-0000-4000-8000-000000000002');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at) values
 ('d2580000-0000-4000-8000-000000000011','d2580000-0000-4000-8000-000000000001',
  'd2580000-0000-4000-8000-000000000001','draft',null,null),
 ('d2580000-0000-4000-8000-000000000012','d2580000-0000-4000-8000-000000000001',
  'd2580000-0000-4000-8000-000000000001','pending',
  'd2580000-0000-4000-8000-000000000001/d2580000-0000-4000-8000-000000000012/existing.png',now());
insert into storage.objects(bucket_id,name) values
 ('oi-evidence','d2580000-0000-4000-8000-000000000001/d2580000-0000-4000-8000-000000000012/existing.png');

-- Simulate a permissive legacy upsert path and verify the retirement policy wins.
create policy test_evidence_update on storage.objects for update to authenticated
  using (bucket_id='oi-evidence') with check (bucket_id='oi-evidence');
create function pg_temp.expect_gone(command text) returns void language plpgsql as $$
begin
  execute command;
  raise exception 'Expected retirement: %',command;
exception when sqlstate 'PT410' then null;
end;
$$;
create function pg_temp.assert_true(result boolean, description text) returns void language plpgsql as $$
begin
  if result is distinct from true then raise exception 'FAIL: %',description; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','d2580000-0000-4000-8000-000000000001',true);
select pg_temp.expect_gone($q$select public.oi_mutate('start_evidence','{"id":"d2580000-0000-4000-8000-000000000013"}')$q$);
select pg_temp.expect_gone($q$select public.oi_mutate('submit_evidence','{"id":"d2580000-0000-4000-8000-000000000011"}')$q$);
select pg_temp.expect_gone($q$select public.oi_mutate('reopen_evidence','{"id":"d2580000-0000-4000-8000-000000000012"}')$q$);
do $$
begin
  begin
    insert into storage.objects(bucket_id,name) values
      ('oi-evidence','d2580000-0000-4000-8000-000000000001/d2580000-0000-4000-8000-000000000011/new.png');
    raise exception 'Old client uploaded to a previously valid draft path';
  exception when insufficient_privilege then null;
  end;
  update storage.objects set metadata='{"overwritten":true}' where bucket_id='oi-evidence';
  if found then raise exception 'Old client modified a retained original'; end if;
end;
$$;
select pg_temp.assert_true((select count(*)=2 from public.oi_evidence_requests),'existing requests remain visible to their owner');
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='oi-evidence'),'old original remains accessible to its owner');

select set_config('request.jwt.claim.sub','d2580000-0000-4000-8000-000000000002',true);
select pg_temp.expect_gone($q$select public.oi_mutate('review_evidence','{"id":"d2580000-0000-4000-8000-000000000012","status":"approved","story_limit":1}')$q$);
select pg_temp.expect_gone($q$select public.oi_review_evidence('{"id":"d2580000-0000-4000-8000-000000000012","status":"approved"}')$q$);
select pg_temp.assert_true((select status='pending' from public.oi_evidence_requests
  where id='d2580000-0000-4000-8000-000000000012'),'old review cannot change stored status');

select set_config('request.jwt.claim.sub','d2580000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(not exists(select 1 from storage.objects where bucket_id='oi-evidence'),'unrelated account cannot read originals');
select pg_temp.assert_true(not exists(select 1 from public.oi_evidence_requests),'writer has no evidence');
select public.oi_mutate('save_story','{"id":"d2580000-0000-4000-8000-000000000020","revision":0,"region_id":"pond",
  "title":"Synthetic story","body":"Synthetic text","theme":"감사","emotion":"기쁨","cucumber_name":"테스트오이",
  "cucumber_asset":"OiCats","card_asset":"MYBlueCard","latitude":36.01261057021347,"longitude":129.3197268697784}');
insert into storage.objects(bucket_id,name) values
 ('oi-story-media','d2580000-0000-4000-8000-000000000003/d2580000-0000-4000-8000-000000000020/synthetic.png');
select public.oi_mutate('attach_media','{"id":"d2580000-0000-4000-8000-000000000020","revision":1,
  "paths":["d2580000-0000-4000-8000-000000000003/d2580000-0000-4000-8000-000000000020/synthetic.png"]}');
select public.oi_mutate('submit_story','{"id":"d2580000-0000-4000-8000-000000000020","revision":2}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true(not exists(select 1 from storage.objects where bucket_id='oi-evidence'),'anonymous users cannot read originals');
select pg_temp.assert_true(not exists(select 1 from public.oi_stories where id='d2580000-0000-4000-8000-000000000020'),'pending story remains private');
set local role authenticated;
select set_config('request.jwt.claim.sub','d2580000-0000-4000-8000-000000000002',true);
select public.oi_mutate('review_story','{"id":"d2580000-0000-4000-8000-000000000020","revision":3,"status":"published"}');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true((select status='published' and grant_id is null from public.oi_stories
  where id='d2580000-0000-4000-8000-000000000020'),'story moderation still publishes without evidence');
select pg_temp.assert_true(exists(select 1 from public.oi_story_media
  where story_id='d2580000-0000-4000-8000-000000000020'),'approved story photo remains public');
rollback;

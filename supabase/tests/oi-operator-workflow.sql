begin;
create function pg_temp.assert_true(result boolean, description text) returns void language plpgsql as $$ begin
  if result is distinct from true then raise exception 'FAIL: %',description; end if;
end; $$;
create function pg_temp.assert_error(command text, expected_state text) returns void language plpgsql as $$ begin
  begin execute command;
  exception when others then
    if sqlstate=expected_state then return; end if;
    raise exception 'Unexpected SQLSTATE %, expected %',sqlstate,expected_state;
  end;
  raise exception 'Expected SQLSTATE %',expected_state;
end; $$;
create function pg_temp.review(decision text) returns jsonb language sql as $$
  select public.oi_review_evidence(jsonb_build_object('id',id,'status',decision,'story_limit',2,
    'review_note','Synthetic workflow review', 'expected_status',status,'expected_object_path',object_path,
    'expected_submitted_at',submitted_at,'expected_reviewed_at',reviewed_at))
  from public.oi_evidence_requests where id='a1450006-0000-4000-8000-000000000010';
$$;
insert into auth.users(id) values('a1450006-0000-4000-8000-000000000001'),
  ('a1450006-0000-4000-8000-000000000002'),('a1450006-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators values('a1450006-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1450006-0000-4000-8000-000000000001',true);
select public.oi_mutate('start_evidence','{"id":"a1450006-0000-4000-8000-000000000010"}');
insert into storage.objects(bucket_id,name) values('oi-evidence','a1450006-0000-4000-8000-000000000001/a1450006-0000-4000-8000-000000000010/synthetic.png');
select public.oi_mutate('submit_evidence','{"id":"a1450006-0000-4000-8000-000000000010","object_path":"a1450006-0000-4000-8000-000000000001/a1450006-0000-4000-8000-000000000010/synthetic.png"}');
select pg_temp.assert_true((select count(*)=0 from public.oi_writing_grants),'submission alone grants no writing rights');
select set_config('request.jwt.claim.sub','a1450006-0000-4000-8000-000000000002',true);
select pg_temp.review('approved');
select pg_temp.assert_true((select count(*)=0 from public.oi_stories),'writing approval alone creates no public story');
select set_config('request.jwt.claim.sub','a1450006-0000-4000-8000-000000000001',true);
select public.oi_mutate('save_story',jsonb_build_object('id','a1450006-0000-4000-8000-000000000020',
  'grant_id',(select id from public.oi_writing_grants),'revision',0,'region_id','pond',
  'title','Synthetic workflow story','body','Synthetic body','theme','감사','emotion','기쁨',
  'cucumber_name','가상 오이','cucumber_asset','OiCats','card_asset','MYBlueCard',
  'latitude',36.01261057021347,'longitude',129.3197268697784));
select public.oi_mutate('submit_story','{"id":"a1450006-0000-4000-8000-000000000020","revision":1}');
select pg_temp.assert_true((select status='pending' from public.oi_stories),'story submission awaits separate publication review');
select set_config('request.jwt.claim.sub','a1450006-0000-4000-8000-000000000002',true);
select public.oi_mutate('review_story','{"id":"a1450006-0000-4000-8000-000000000020","revision":2,"status":"published"}');
select set_config('request.jwt.claim.sub','a1450006-0000-4000-8000-000000000003',true);
select public.oi_mutate('collect','{"id":"a1450006-0000-4000-8000-000000000020"}');
select pg_temp.assert_true((select count(*)=1 from public.oi_collections),'collector receives collection only');
select pg_temp.assert_true((select count(*)=0 from public.oi_writing_grants),'collector receives no author grant');
select pg_temp.assert_error($q$select public.oi_mutate('review_story','{"id":"a1450006-0000-4000-8000-000000000020","revision":3,"status":"hidden"}')$q$,'42501');
select set_config('request.jwt.claim.sub','a1450006-0000-4000-8000-000000000002',true);
select pg_temp.review('revoked');
select pg_temp.assert_true((select status='hidden' from public.oi_stories),'evidence revocation hides linked story');
select pg_temp.assert_true((select revoked_at is not null from public.oi_writing_grants),'writing grant revoked');
select pg_temp.assert_true((select count(*)=2 from public.oi_evidence_history),'submission and approved snapshots retained');
select set_config('test.operator.audit',public.oi_operator_audit(now()-interval '1 minute',now()+interval '1 minute')::text,true);
select pg_temp.assert_true(jsonb_array_length(current_setting('test.operator.audit')::jsonb->'records')=4,'operator RPC reads existing submission/publication/evidence audit writes');
select pg_temp.assert_true((select count(*)=2 from jsonb_array_elements(current_setting('test.operator.audit')::jsonb->'records') r
  where r->>'action' in ('review_evidence:approved','review_evidence:revoked')),'both evidence decisions audited');
select pg_temp.assert_true((select count(*)=1 from jsonb_array_elements(current_setting('test.operator.audit')::jsonb->'records') r
  where r->>'action'='review_story'),'publication review audited without inventing a status value');
select set_config('request.jwt.claim.sub','a1450006-0000-4000-8000-000000000001',true);
select pg_temp.assert_error($q$select public.oi_mutate('reopen_story','{"id":"a1450006-0000-4000-8000-000000000020","revision":4}')$q$,'42501');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.assert_true((select count(*)=0 from public.oi_stories),'revoked story no longer public');
rollback;

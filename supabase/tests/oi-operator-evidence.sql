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
    raise exception 'Unexpected SQLSTATE %, expected %',sqlstate,expected_state;
  end;
  raise exception 'Expected error %',expected_state;
end; $$;
create function pg_temp.review_payload(target uuid, decision text) returns jsonb
language sql as $$
  select jsonb_build_object('id',id,'status',decision,'story_limit',3,'review_note','Synthetic review only',
    'expected_status',status,'expected_object_path',object_path,
    'expected_submitted_at',submitted_at,'expected_reviewed_at',reviewed_at)
  from public.oi_evidence_requests where id=target;
$$;
insert into auth.users(id) values('e1450000-0000-4000-8000-000000000001'),('e1450000-0000-4000-8000-000000000002');
insert into benchmark_private.oi_operators values('e1450000-0000-4000-8000-000000000002');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at)
select id,'e1450000-0000-4000-8000-000000000001','e1450000-0000-4000-8000-000000000001','pending',
  'e1450000-0000-4000-8000-000000000001/'||id::text||'/synthetic.png','2026-11-04T01:00:00Z'
from unnest(array['e1450000-0000-4000-8000-000000000010'::uuid,
  'e1450000-0000-4000-8000-000000000011'::uuid,'e1450000-0000-4000-8000-000000000012'::uuid]) id;
set local role anon;
select pg_temp.assert_error($q$select public.oi_review_evidence('{}')$q$,'42501');
set local role authenticated;
select set_config('request.jwt.claim.sub','e1450000-0000-4000-8000-000000000001',true);
select pg_temp.assert_error($q$select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000010','approved'))$q$,'42501');
select set_config('request.jwt.claim.sub','e1450000-0000-4000-8000-000000000002',true);
select pg_temp.assert_error($q$select public.oi_review_evidence('{"id":"e1450000-0000-4000-8000-000000000010","status":"approved"}')$q$,'22023');
select pg_temp.assert_error($q$select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000010','approved')||'{"story_limit":0}')$q$,'22023');
select pg_temp.assert_error($q$select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000010','rejected')||'{"review_note":"  "}')$q$,'22023');
select pg_temp.assert_error($q$select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000010','approved')||'{"expected_submitted_at":"2026-11-04T00:00:00Z"}')$q$,'40001');
select pg_temp.assert_error($q$select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000010','approved')||'{"expected_object_path":"stale.png"}')$q$,'40001');
select set_config('test.evidence_snapshot',pg_temp.review_payload('e1450000-0000-4000-8000-000000000010','approved')::text,true);
select public.oi_review_evidence(current_setting('test.evidence_snapshot')::jsonb);
select pg_temp.assert_true((select story_limit=3 from public.oi_writing_grants where evidence_id='e1450000-0000-4000-8000-000000000010'),'explicit grant count');
select pg_temp.assert_error($q$select public.oi_review_evidence(current_setting('test.evidence_snapshot')::jsonb)$q$,'40001');
select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000011','changes_requested'));
select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000012','rejected'));
select pg_temp.assert_true((select count(*)=1 from public.oi_writing_grants where evidence_id::text like 'e145%'),'no grants for other decisions');
-- Revocation must keep the existing story-hiding and audit/history semantics.
reset role;
insert into public.oi_stories(id,user_id,storage_owner_id,grant_id,region_id,title,body,theme,emotion,cucumber_name,cucumber_asset,card_asset,latitude,longitude,status)
select 'e1450000-0000-4000-8000-000000000020','e1450000-0000-4000-8000-000000000001','e1450000-0000-4000-8000-000000000001',id,'pond',
  'Synthetic title','Synthetic body','감사','기쁨','Synthetic cucumber','OiCats','MYBlueCard',36,129,'published'
from public.oi_writing_grants where evidence_id='e1450000-0000-4000-8000-000000000010';
set local role authenticated;
select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000010','revoked'));
select pg_temp.assert_true((select revoked_at is not null from public.oi_writing_grants where evidence_id='e1450000-0000-4000-8000-000000000010'),'grant revoked');
select pg_temp.assert_true((select status='hidden' and revision=2 from public.oi_stories where id='e1450000-0000-4000-8000-000000000020'),'linked story hidden');
select pg_temp.assert_true((select count(*)=2 from public.oi_evidence_history where request_id='e1450000-0000-4000-8000-000000000010'),'history preserved');
reset role;
select pg_temp.assert_true((select count(*)=4 from benchmark_private.oi_audit where target_id::text like 'e145%'),'audit preserved');
-- A new pending submission with the same path must reject the previous snapshot.
update public.oi_evidence_requests set status='pending',submitted_at='2026-11-04T02:00:00Z',reviewed_at=null
where id='e1450000-0000-4000-8000-000000000012';
set local role authenticated;
select pg_temp.assert_error($q$select public.oi_review_evidence(pg_temp.review_payload('e1450000-0000-4000-8000-000000000012','approved')||'{"expected_submitted_at":"2026-11-04T01:00:00Z"}')$q$,'40001');
rollback;

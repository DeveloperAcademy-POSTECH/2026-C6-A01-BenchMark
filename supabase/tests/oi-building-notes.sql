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
 ('59170000-0000-4000-8000-000000000001'),('59170000-0000-4000-8000-000000000002'),
 ('59170000-0000-4000-8000-000000000003'),('59170000-0000-4000-8000-000000000004');
insert into benchmark_private.oi_operators(user_id) values('59170000-0000-4000-8000-000000000003');
update public.oi_profiles set nickname='Synthetic author',admission_year='2026',department='Public department'
 where id='59170000-0000-4000-8000-000000000001';
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_building_notes('136182168')='[]'::jsonb,'anonymous read empty building');
select pg_temp.check_error($q$select * from benchmark_private.oi_building_notes$q$,'42501');
select pg_temp.check_error($q$select public.oi_post_building_note(gen_random_uuid(),'136182168','not authenticated')$q$,'42501');
set local role authenticated;
select set_config('request.jwt.claim.sub','59170000-0000-4000-8000-000000000001',true);
select pg_temp.check_error($q$select public.oi_post_building_note(gen_random_uuid(),'invented','text')$q$,'22023');
select pg_temp.check_error($q$select public.oi_post_building_note(gen_random_uuid(),'136182168',E' \n\t')$q$,'22023');
select pg_temp.check_error($q$select public.oi_post_building_note(gen_random_uuid(),'136182168',repeat('가',141))$q$,'22023');
select public.oi_post_building_note('59170000-0000-4000-8000-000000000011','136182168','  Synthetic note  ');
select pg_temp.check_true(public.oi_post_building_note('59170000-0000-4000-8000-000000000011','136182168','Synthetic note')->>'id'='59170000-0000-4000-8000-000000000011','retry uses same ID');
select pg_temp.check_error($q$select public.oi_post_building_note('59170000-0000-4000-8000-000000000011','136182168','different')$q$,'PT409');
select pg_temp.check_error($q$select public.oi_post_building_note(gen_random_uuid(),'136182168','burst')$q$,'PT429');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(jsonb_array_length(public.oi_building_notes('136182168'))=1,'published immediately without story approval');
select pg_temp.check_true(public.oi_building_notes('136182168')->0->>'department'='Public department','only public academic label returned');
select pg_temp.check_true(not (public.oi_building_notes('136182168')->0 ? 'email') and not (public.oi_building_notes('136182168')->0 ? 'school_department'),'no private metadata');
select pg_temp.check_true(public.oi_building_notes('135973505')='[]'::jsonb,'no cross-building leak');
set local role authenticated;
select set_config('request.jwt.claim.sub','59170000-0000-4000-8000-000000000002',true);
select pg_temp.check_error($q$select public.oi_delete_building_note('59170000-0000-4000-8000-000000000011')$q$,'42501');
select pg_temp.check_error($q$select public.oi_building_note_reports()$q$,'42501');
select set_config('test.note_report',public.oi_report_building_note('59170000-0000-4000-8000-000000000011','abuse','Synthetic report')::text,true);
select pg_temp.check_true(public.oi_report_building_note('59170000-0000-4000-8000-000000000011','abuse','retry')->>'id'=current_setting('test.note_report')::jsonb->>'id','report idempotency');
select pg_temp.check_error($q$select public.oi_review_building_note((current_setting('test.note_report')::jsonb->>'id')::uuid,'deleted','test')$q$,'42501');
select set_config('request.jwt.claim.sub','59170000-0000-4000-8000-000000000003',true);
select pg_temp.check_true(jsonb_array_length(public.oi_building_note_reports())=1,'operator report inbox');
select public.oi_review_building_note((current_setting('test.note_report')::jsonb->>'id')::uuid,'deleted','Synthetic moderation');
select pg_temp.check_error($q$select public.oi_review_building_note((current_setting('test.note_report')::jsonb->>'id')::uuid,'dismissed','test')$q$,'PT409');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_building_notes('136182168')='[]'::jsonb,'review deletion removes public note');
reset role;
-- More than one page, same timestamp tie-break, and merged/deleting/restricted authors.
insert into benchmark_private.oi_building_notes(id,building_id,author_member_id,body,created_at)
select ('59170000-0000-4000-8001-'||lpad(i::text,12,'0'))::uuid,'136182168','59170000-0000-4000-8000-000000000001','Synthetic page '||i,now()-interval '1 day'
from generate_series(1,51) i;
set local role anon;
select pg_temp.check_true(jsonb_array_length(public.oi_building_notes('136182168'))=50,'bounded page');
select set_config('test.note_cursor',(public.oi_building_notes('136182168')->49)::text,true);
select pg_temp.check_true(jsonb_array_length(public.oi_building_notes('136182168',
 (current_setting('test.note_cursor')::jsonb->>'created_at')::timestamptz,
 (current_setting('test.note_cursor')::jsonb->>'id')::uuid))=1,'stable cursor with same timestamps');
reset role;
update benchmark_private.oi_account_members set account_id='59170000-0000-4000-8000-000000000004' where auth_user_id='59170000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','59170000-0000-4000-8000-000000000004',true);
select pg_temp.check_true(public.oi_building_notes('136182168')->0->>'author_id'='59170000-0000-4000-8000-000000000004','ownership follows merged account');
select public.oi_delete_building_note('59170000-0000-4000-8001-000000000001');
select public.oi_delete_building_note('59170000-0000-4000-8001-000000000001');
reset role;
insert into benchmark_private.oi_content_restrictions(member_id,note) values('59170000-0000-4000-8000-000000000001','Synthetic restriction');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_building_notes('136182168')='[]'::jsonb,'restricted authors hidden even after merge');
set local role authenticated;
select set_config('request.jwt.claim.sub','59170000-0000-4000-8000-000000000004',true);
select pg_temp.check_error($q$select public.oi_post_building_note(gen_random_uuid(),'136182168','restricted')$q$,'42501');
reset role;
update benchmark_private.oi_content_restrictions set active=false where member_id='59170000-0000-4000-8000-000000000001';
insert into benchmark_private.oi_account_deletions(account_id) values('59170000-0000-4000-8000-000000000004');
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.check_true(public.oi_building_notes('136182168')='[]'::jsonb,'deleting accounts hidden');
reset role;
select pg_temp.check_true((select count(*)=1 from benchmark_private.oi_audit where action='building_note:deleted' and target_id='59170000-0000-4000-8000-000000000011'),'moderation is audited');
insert into benchmark_private.oi_audit(actor_id,action,target_id) values
 ('59170000-0000-4000-8000-000000000003','building_note_ai:keep','59170000-0000-4000-8000-000000000011'),
 ('59170000-0000-4000-8000-000000000003','education:deleted','59170000-0000-4000-8000-000000000011'),
 ('59170000-0000-4000-8000-000000000003','content:hidden','59170000-0000-4000-8000-000000000011');
delete from benchmark_private.oi_account_members where auth_user_id='59170000-0000-4000-8000-000000000001';
select pg_temp.check_true((select count(*)=0 from benchmark_private.oi_building_notes where author_member_id='59170000-0000-4000-8000-000000000001'),'account removal cascades notes');
select pg_temp.check_true((select count(*)=0 from benchmark_private.oi_audit
 where target_id='59170000-0000-4000-8000-000000000011' and action in ('building_note:deleted','building_note_ai:keep')),
 'account removal clears manual and AI note audits recorded by another account');
select pg_temp.check_true((select count(*)=2 from benchmark_private.oi_audit
 where target_id='59170000-0000-4000-8000-000000000011' and action in ('education:deleted','content:hidden')),
 'account removal preserves unrelated audit channels with the same target UUID');
select 'PASS: building notes authentication, isolation, publication, idempotency, validation, reporting, moderation, cursor, merge and deletion' as result;
rollback;

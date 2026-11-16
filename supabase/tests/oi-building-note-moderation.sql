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
 ('59190000-0000-4000-8000-000000000001'),('59190000-0000-4000-8000-000000000002'),('59190000-0000-4000-8000-000000000003');
insert into auth.sessions(id,user_id) values
 ('59190000-0000-4000-8001-000000000002','59190000-0000-4000-8000-000000000002'),
 ('59190000-0000-4000-8001-000000000003','59190000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_operators(user_id) values('59190000-0000-4000-8000-000000000003');
insert into benchmark_private.oi_building_notes(id,building_id,author_member_id,body)
 select ('59190000-0000-4000-8002-'||lpad(i::text,12,'0'))::uuid,'136182168',
 '59190000-0000-4000-8000-000000000001','Synthetic moderation fixture '||i from generate_series(1,6) i;
insert into benchmark_private.oi_building_note_reports(id,note_id,reporter_member_id,reason,detail)
 select ('59190000-0000-4000-8003-'||lpad(i::text,12,'0'))::uuid,
 ('59190000-0000-4000-8002-'||lpad(i::text,12,'0'))::uuid,'59190000-0000-4000-8000-000000000002','abuse','Synthetic report' from generate_series(1,6) i;
set local role authenticated;
select pg_temp.check_error($q$select public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000001')$q$,'42501');
set local role service_role;
select pg_temp.check_error($q$select public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002',gen_random_uuid(),'59190000-0000-4000-8003-000000000001')$q$,'PT401');
select pg_temp.check_error($q$select public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002',gen_random_uuid())$q$,'42501');
select set_config('test.ai',public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000001')::text,true);
select pg_temp.check_true(current_setting('test.ai')::jsonb->>'body'='Synthetic moderation fixture 1','only stored note text');
select pg_temp.check_true(not (current_setting('test.ai')::jsonb ? 'detail'),'no private report detail in snapshot');
select pg_temp.check_true(public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000001')->>'ready'='false','lease avoids duplicate AI cost');
select pg_temp.check_error($q$select public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000001',gen_random_uuid(),current_setting('test.ai')::jsonb->>'snapshot','remove','spam')$q$,'PT409');
select pg_temp.check_error($q$select public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000001',(current_setting('test.ai')::jsonb->>'claim')::uuid,current_setting('test.ai')::jsonb->>'snapshot','remove','made_up')$q$,'22023');
select pg_temp.check_true(public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000001',(current_setting('test.ai')::jsonb->>'claim')::uuid,current_setting('test.ai')::jsonb->>'snapshot','remove','harassment')->>'status'='deleted','AI clear violation deleted');
select pg_temp.check_true(public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000001')->>'ready'='false','finished result not reviewed twice');
reset role;
select pg_temp.check_true((select status='deleted' from benchmark_private.oi_building_notes where id='59190000-0000-4000-8002-000000000001'),'AI deletion removed note');
select pg_temp.check_true((select count(*)=1 from benchmark_private.oi_audit where target_id='59190000-0000-4000-8002-000000000001' and action='building_note_ai:remove:harassment'),'AI result audited once');

-- Uncertain result remains in the human queue, while an ordinary comment remains public.
set local role service_role;
select set_config('test.ai',public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000002')::text,true);
select pg_temp.check_true(public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000002',(current_setting('test.ai')::jsonb->>'claim')::uuid,current_setting('test.ai')::jsonb->>'snapshot','manual_review',null)->>'status'='pending','uncertain result queued');
select pg_temp.check_true(public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000002')->>'ready'='false','uncertain result does not trigger retry loop');
select set_config('test.ai',public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000003')::text,true);
select pg_temp.check_true(public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000003',(current_setting('test.ai')::jsonb->>'claim')::uuid,current_setting('test.ai')::jsonb->>'snapshot','keep',null)->>'status'='dismissed','non-violation dismissed');

-- Operator decision wins over an in-flight AI result.
select set_config('test.ai',public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000004')::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub','59190000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"59190000-0000-4000-8000-000000000003","session_id":"59190000-0000-4000-8001-000000000003","role":"authenticated"}',true);
select public.oi_review_building_note('59190000-0000-4000-8003-000000000004','dismissed','Synthetic operator decision');
set local role service_role;
select pg_temp.check_true(public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000004',(current_setting('test.ai')::jsonb->>'claim')::uuid,current_setting('test.ai')::jsonb->>'snapshot','remove','spam')->>'status'='dismissed','late AI cannot overwrite manual review');
reset role;
select pg_temp.check_true((select status='published' from benchmark_private.oi_building_notes where id='59190000-0000-4000-8002-000000000004'),'operator kept note remains public');

-- Ownership, lease retries, and session revocation are checked server-side.
update benchmark_private.oi_building_note_reports set reporter_member_id='59190000-0000-4000-8000-000000000001' where id='59190000-0000-4000-8003-000000000005';
set local role service_role;
select pg_temp.check_error($q$select public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000005')$q$,'42501');
reset role;
update benchmark_private.oi_building_note_reports set ai_attempts=3 where id='59190000-0000-4000-8003-000000000006';
set local role service_role;
select pg_temp.check_true(public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000006')->>'ready'='false','AI attempts bounded across workers');
reset role;
update benchmark_private.oi_building_note_reports set ai_attempts=0 where id='59190000-0000-4000-8003-000000000006';
set local role service_role;
select set_config('test.ai',public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000006')::text,true);
reset role;
delete from auth.sessions where id='59190000-0000-4000-8001-000000000002';
set local role service_role;
select pg_temp.check_error($q$select public.oi_moderate_building_note('59190000-0000-4000-8000-000000000002','59190000-0000-4000-8001-000000000002','59190000-0000-4000-8003-000000000006',(current_setting('test.ai')::jsonb->>'claim')::uuid,current_setting('test.ai')::jsonb->>'snapshot','remove','spam')$q$,'PT401');
rollback;

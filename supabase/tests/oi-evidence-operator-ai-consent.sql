begin;
insert into auth.users(id) values ('ce252000-0000-4000-8000-000000000001'),('ce252000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claim.sub','ce252000-0000-4000-8000-000000000001',true);
select public.oi_mutate('start_evidence','{"id":"ce252000-0000-4000-8000-000000000011"}');
insert into storage.objects(bucket_id,name) values
 ('oi-evidence','ce252000-0000-4000-8000-000000000001/ce252000-0000-4000-8000-000000000011/first.png');

select set_config('request.jwt.claim.sub','ce252000-0000-4000-8000-000000000002',true);
do $$ begin
  begin
    perform public.oi_mutate('submit_evidence','{"id":"ce252000-0000-4000-8000-000000000011","object_path":"ce252000-0000-4000-8000-000000000001/ce252000-0000-4000-8000-000000000011/first.png","operator_ai_consent":true}');
    raise exception 'another account could consent';
  exception when insufficient_privilege then null; end;
end; $$;

select set_config('request.jwt.claim.sub','ce252000-0000-4000-8000-000000000001',true);
do $$
declare payload jsonb := '{"id":"ce252000-0000-4000-8000-000000000011","object_path":"ce252000-0000-4000-8000-000000000001/ce252000-0000-4000-8000-000000000011/first.png"}';
  receipt jsonb;
begin
  receipt := public.oi_mutate('submit_evidence',payload || '{"operator_ai_consent":true}');
  if receipt->>'operator_ai_consented_at' is null or receipt->>'operator_ai_consented_at' is distinct from receipt->>'submitted_at' then
    raise exception 'explicit consent was not recorded for the submission';
  end if;
  if public.oi_mutate('submit_evidence',payload) is distinct from receipt then
    raise exception 'a replay changed the already submitted consent';
  end if;
end; $$;

reset role;
update public.oi_evidence_requests set status='changes_requested' where id='ce252000-0000-4000-8000-000000000011';

set local role authenticated;
do $$
declare payload jsonb := '{"id":"ce252000-0000-4000-8000-000000000011","object_path":"ce252000-0000-4000-8000-000000000001/ce252000-0000-4000-8000-000000000011/second.png"}';
begin
  if public.oi_mutate('reopen_evidence','{"id":"ce252000-0000-4000-8000-000000000011","operation_id":"ce252000-0000-4000-8000-000000000012","expected_status":"changes_requested","expected_object_path":"ce252000-0000-4000-8000-000000000001/ce252000-0000-4000-8000-000000000011/first.png"}')
     ->>'operator_ai_consented_at' is not null then raise exception 'reopening kept prior consent'; end if;
  insert into storage.objects(bucket_id,name) values ('oi-evidence',payload->>'object_path');
  if public.oi_mutate('submit_evidence',payload)->>'operator_ai_consented_at' is not null then
    raise exception 'submission without consent inherited permission';
  end if;
  if public.oi_mutate('submit_evidence',payload || '{"operator_ai_consent":true}')->>'operator_ai_consented_at' is not null then
    raise exception 'a replay granted consent retroactively';
  end if;
end; $$;
rollback;

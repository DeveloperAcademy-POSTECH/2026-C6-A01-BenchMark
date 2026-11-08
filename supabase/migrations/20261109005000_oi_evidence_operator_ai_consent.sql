begin;

alter table public.oi_evidence_requests add column operator_ai_consented_at timestamptz;
alter table public.oi_evidence_requests add constraint oi_evidence_operator_ai_consent_matches_submission check (
  operator_ai_consented_at is null or (object_path is not null and submitted_at is not null and operator_ai_consented_at=submitted_at)
);

-- The owner-checked submit transition records explicit consent with the uploaded file.
-- A replay of a successful submit keeps its original consent; reopening clears it.
do $patch$
declare
  submit_definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure);
  reopen_definition text := pg_get_functiondef('benchmark_private.oi_reopen_evidence(jsonb)'::regprocedure);
  submit_anchor text := $sql$set status='pending',object_path=path,submitted_at=now()$sql$;
  reopen_anchor text := 'submitted_at=null,reviewed_at=null,resume_operation_id=operation_id';
begin
  if (length(submit_definition)-length(replace(submit_definition,submit_anchor,'')))<>length(submit_anchor)
    or (length(reopen_definition)-length(replace(reopen_definition,reopen_anchor,'')))<>length(reopen_anchor) then
    raise exception 'Evidence submission definitions changed; review consent migration';
  end if;
  execute replace(submit_definition,submit_anchor,submit_anchor || $sql$,
      operator_ai_consented_at=case when payload->'operator_ai_consent'='true'::jsonb then now() end$sql$);
  execute replace(reopen_definition,reopen_anchor,reopen_anchor || ',operator_ai_consented_at=null');
end;
$patch$;

notify pgrst,'reload schema';
commit;

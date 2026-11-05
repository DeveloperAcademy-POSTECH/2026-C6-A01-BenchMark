begin;
-- Compare the viewed submission while holding the same lock used by the mutation.
-- The existing mutation retains grant creation, revocation, history and audit behavior.
create function benchmark_private.oi_review_evidence(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  request public.oi_evidence_requests;
  decision text := payload->>'status';
  note text := btrim(coalesce(payload->>'review_note',''));
begin
  if not benchmark_private.oi_is_operator() then
    raise exception 'Operator required' using errcode='42501';
  end if;
  if not (payload ?& array['expected_status','expected_object_path','expected_submitted_at','expected_reviewed_at']) then
    raise exception 'Submission snapshot required' using errcode='22023';
  end if;
  select * into request from public.oi_evidence_requests where id=(payload->>'id')::uuid for update;
  if not found or request.object_path is null or request.submitted_at is null
    or request.status is distinct from payload->>'expected_status'
    or request.object_path is distinct from payload->>'expected_object_path'
    or request.submitted_at is distinct from (payload->>'expected_submitted_at')::timestamptz
    or request.reviewed_at is distinct from (payload->>'expected_reviewed_at')::timestamptz then
    raise exception 'Submission changed; refresh before review' using errcode='40001';
  end if;
  if length(note)>2000 or (decision in ('changes_requested','rejected','revoked') and note='') then
    raise exception 'Review note required, maximum 2000 characters' using errcode='22023';
  end if;
  return benchmark_private.oi_mutate('review_evidence',payload || jsonb_build_object('review_note',note));
end;
$$;
revoke all on function benchmark_private.oi_review_evidence(jsonb) from public,anon;
grant execute on function benchmark_private.oi_review_evidence(jsonb) to authenticated;
create function public.oi_review_evidence(p_payload jsonb) returns jsonb
language sql security invoker set search_path='' as $$
  select benchmark_private.oi_review_evidence(p_payload);
$$;
revoke all on function public.oi_review_evidence(jsonb) from public,anon;
grant execute on function public.oi_review_evidence(jsonb) to authenticated;
notify pgrst,'reload schema';
commit;

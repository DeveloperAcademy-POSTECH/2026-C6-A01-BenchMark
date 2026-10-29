begin;
alter table public.oi_evidence_requests add column resume_operation_id uuid;
create table public.oi_evidence_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.oi_evidence_requests(id),
  status text not null,
  object_path text not null,
  review_note text,
  reviewer_id uuid,
  recorded_at timestamptz not null default now()
);
create index oi_evidence_history_request_idx on public.oi_evidence_history(request_id,recorded_at);
alter table public.oi_evidence_history enable row level security;
revoke all on public.oi_evidence_history from public,anon,authenticated;
grant select on public.oi_evidence_history to authenticated;
create policy oi_evidence_history_read on public.oi_evidence_history for select to authenticated
using (exists(select 1 from public.oi_evidence_requests request
  where request.id=oi_evidence_history.request_id and
    (request.user_id=(select auth.uid()) or (select benchmark_private.oi_is_operator()))));

create function benchmark_private.oi_record_evidence_history() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if old.status<>new.status and old.object_path is not null then
    insert into public.oi_evidence_history(request_id,status,object_path,review_note,reviewer_id)
      values(old.id,old.status,old.object_path,old.review_note,old.reviewer_id);
  end if;
  return new;
end;
$$;
revoke all on function benchmark_private.oi_record_evidence_history() from public,anon,authenticated;
create trigger oi_evidence_history before update of status on public.oi_evidence_requests
for each row execute function benchmark_private.oi_record_evidence_history();

create function benchmark_private.oi_reopen_evidence(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  request public.oi_evidence_requests;
  operation_id uuid := (payload->>'operation_id')::uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if operation_id is null then raise exception 'Operation ID required' using errcode='22023'; end if;
  select * into request from public.oi_evidence_requests where id=(payload->>'id')::uuid and user_id=auth.uid() for update;
  if not found then raise exception 'Request unavailable' using errcode='42501'; end if;
  if request.status='draft' and request.resume_operation_id=operation_id then return to_jsonb(request); end if;
  if request.status not in ('changes_requested','rejected')
    or request.status is distinct from payload->>'expected_status'
    or request.object_path is distinct from payload->>'expected_object_path' then
    raise exception 'Application changed; refresh before resubmission' using errcode='40001';
  end if;
  update public.oi_evidence_requests set status='draft',object_path=null,review_note=null,reviewer_id=null,
    submitted_at=null,reviewed_at=null,resume_operation_id=operation_id where id=request.id returning * into request;
  return to_jsonb(request);
end;
$$;
revoke all on function benchmark_private.oi_reopen_evidence(jsonb) from public,anon;
grant execute on function benchmark_private.oi_reopen_evidence(jsonb) to authenticated;

create or replace function public.oi_mutate(p_action text,p_payload jsonb) returns jsonb
language sql security invoker set search_path='' as $$
  select case when p_action='reopen_evidence' then benchmark_private.oi_reopen_evidence(p_payload)
    else benchmark_private.oi_mutate(p_action,p_payload) end;
$$;

create policy oi_media_objects_staging_read on storage.objects for select to authenticated
using (bucket_id='oi-story-media' and (storage.foldername(name))[1]=(select auth.uid())::text
  and exists(select 1 from public.oi_stories story where story.id::text=(storage.foldername(name))[2]
    and story.user_id=(select auth.uid()) and story.status='draft'));
commit;

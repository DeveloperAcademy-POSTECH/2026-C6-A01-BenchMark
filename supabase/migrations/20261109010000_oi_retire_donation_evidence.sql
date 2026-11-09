begin;

-- Keep the existing story implementation on both supported database histories.
-- Replace only the old donation cases; do not change or remove retained records.
do $patch$
declare
  definition text := pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure);
  standalone_case text := $sql$  if action='start_evidence' then$sql$;
  chained_case text := $sql$  elsif action='start_evidence' then$sql$;
  first_case text := case when strpos(definition,standalone_case)>0 then standalone_case else chained_case end;
  next_case text := $sql$  elsif action='save_story' then$sql$;
  first_position integer := strpos(definition,first_case);
  next_position integer := strpos(definition,next_case);
  donation_cases text;
begin
  if first_position=0 or next_position<=first_position
    or (strpos(definition,standalone_case)>0 and strpos(definition,chained_case)>0)
    or (length(definition)-length(replace(definition,first_case,'')))<>length(first_case)
    or (length(definition)-length(replace(definition,next_case,'')))<>length(next_case) then
    raise exception 'Donation mutation definition changed; review retirement migration';
  end if;
  donation_cases := substr(definition,first_position+length(first_case),next_position-first_position-length(first_case));
  if strpos(donation_cases,$sql$  elsif action='submit_evidence' then$sql$)=0
    or strpos(donation_cases,$sql$  elsif action='review_evidence' then$sql$)=0
    or length(donation_cases)-length(replace(donation_cases,'  elsif action=',''))<>2*length('  elsif action=') then
    raise exception 'Unexpected cases in donation mutation; review retirement migration';
  end if;
  definition := overlay(definition placing
    replace(first_case,$sql$action='start_evidence'$sql$,
      $sql$action in ('start_evidence','submit_evidence','review_evidence','reopen_evidence')$sql$)
    || $sql$
    raise sqlstate 'PT410' using message='Donation evidence intake is closed';
$sql$ from first_position for next_position-first_position);
  execute replace(definition,'  request public.oi_evidence_requests;' || chr(10),'');
end;
$patch$;

-- Older builds also use these dedicated RPC paths.
create or replace function benchmark_private.oi_reopen_evidence(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  raise sqlstate 'PT410' using message='Donation evidence intake is closed';
end;
$$;

create or replace function benchmark_private.oi_review_evidence(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  raise sqlstate 'PT410' using message='Donation evidence review is closed';
end;
$$;

-- An old draft may have a valid upload path. Deny even if an older policy grants
-- it, including replacement of an existing object. Service-role cleanup and
-- the existing private SELECT policy are unaffected.
create policy oi_retired_evidence_no_insert on storage.objects as restrictive for insert to anon,authenticated
  with check (bucket_id is distinct from 'oi-evidence');
create policy oi_retired_evidence_no_update on storage.objects as restrictive for update to anon,authenticated
  using (bucket_id is distinct from 'oi-evidence')
  with check (bucket_id is distinct from 'oi-evidence');

notify pgrst,'reload schema';
commit;

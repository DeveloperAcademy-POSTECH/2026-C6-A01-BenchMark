begin;

-- Generate the dedicated HMAC key inside Postgres and keep it in encrypted Vault
-- storage. Never interpolate plaintext into migration text, output, or logs. An
-- existing named key must be reused so credential rotation cannot reset matching.
do $$
begin
  perform pg_advisory_xact_lock(hashtextextended('oi_evidence_fingerprint_key', 161));
  if not exists(select 1 from vault.secrets where name = 'oi_evidence_fingerprint_key') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'),
      'oi_evidence_fingerprint_key', 'Stable server-only HMAC key for private donation evidence fingerprints');
  end if;
end;
$$;

create function benchmark_private.oi_evidence_fingerprint_key() returns text
language plpgsql stable security definer set search_path = '' as $$
declare key_value text;
begin
  select decrypted_secret into key_value from vault.decrypted_secrets where name = 'oi_evidence_fingerprint_key';
  if not found or key_value is null or key_value !~ '^[0-9a-f]{64}$' then
    raise exception 'evidence_fingerprint_key_unavailable' using errcode = '55000';
  end if;
  return key_value;
end;
$$;
revoke all on function benchmark_private.oi_evidence_fingerprint_key() from public, anon, authenticated, service_role;
grant usage on schema benchmark_private to service_role;
grant execute on function benchmark_private.oi_evidence_fingerprint_key() to service_role;
create function public.oi_evidence_fingerprint_key() returns text
language sql stable security invoker set search_path = '' as $$
  select benchmark_private.oi_evidence_fingerprint_key();
$$;
revoke all on function public.oi_evidence_fingerprint_key() from public, anon, authenticated, service_role;
grant execute on function public.oi_evidence_fingerprint_key() to service_role;

-- The request reference owns the fingerprint. Account merge may change its
-- current user_id without rewriting this private ledger or its Storage prefix.
create table benchmark_private.oi_evidence_fingerprints (
  evidence_id uuid primary key references public.oi_evidence_requests(id) on delete cascade,
  submitted_at timestamptz not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  semantic_digest text check (semantic_digest is null or semantic_digest ~ '^[0-9a-f]{64}$')
);
create index oi_evidence_fingerprints_sha256_idx
  on benchmark_private.oi_evidence_fingerprints(sha256);
create index oi_evidence_fingerprints_semantic_idx
  on benchmark_private.oi_evidence_fingerprints(semantic_digest) where semantic_digest is not null;
alter table benchmark_private.oi_evidence_fingerprints enable row level security;
revoke all on benchmark_private.oi_evidence_fingerprints from public, anon, authenticated, service_role;

-- Retire the previous upload immediately, even when no replacement analysis has
-- run yet. Review status and canonical owner changes keep the current fingerprint.
create function benchmark_private.oi_retire_evidence_fingerprint() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.object_path is distinct from new.object_path
    or old.submitted_at is distinct from new.submitted_at then
    delete from benchmark_private.oi_evidence_fingerprints where evidence_id = old.id;
  end if;
  return new;
end;
$$;
revoke all on function benchmark_private.oi_retire_evidence_fingerprint() from public, anon, authenticated, service_role;
create trigger oi_evidence_fingerprint_retirement
  after update of object_path, submitted_at on public.oi_evidence_requests
  for each row execute function benchmark_private.oi_retire_evidence_fingerprint();

create function benchmark_private.oi_register_evidence_fingerprint(
  p_evidence_id uuid, p_user_id uuid, p_object_path text, p_submitted_at timestamptz,
  p_sha256 text, p_semantic_digest text default null
) returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '15s' as $$
declare
  request public.oi_evidence_requests;
  prior benchmark_private.oi_evidence_fingerprints;
  path_parts text[];
  lock_key bigint;
  same_request boolean;
  exact_duplicate boolean;
  semantic_duplicate boolean;
  effective_semantic_digest text;
begin
  if p_evidence_id is null or p_user_id is null or p_object_path is null
    or p_submitted_at is null or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$'
    or (p_semantic_digest is not null and p_semantic_digest !~ '^[0-9a-f]{64}$') then
    raise exception 'invalid_evidence_fingerprint' using errcode = '22023';
  end if;

  select * into request from public.oi_evidence_requests where id = p_evidence_id for update;
  if not found or request.user_id <> p_user_id or request.status <> 'pending'
    or request.object_path is distinct from p_object_path
    or request.submitted_at is distinct from p_submitted_at then
    raise exception 'evidence_changed_or_unavailable' using errcode = '40001';
  end if;
  path_parts := string_to_array(p_object_path, '/');
  if cardinality(path_parts) <> 3 or path_parts[1] <> request.storage_owner_id::text
    or path_parts[2] <> request.id::text or path_parts[3] in ('', '.', '..')
    or position(chr(92) in p_object_path) > 0 or p_object_path ~ '[[:cntrl:]]' then
    raise exception 'invalid_evidence_reference' using errcode = '22023';
  end if;

  select * into prior from benchmark_private.oi_evidence_fingerprints where evidence_id = p_evidence_id;
  same_request := found and prior.submitted_at = p_submitted_at and prior.sha256 = p_sha256;
  -- An unchanged upload must not lose its previously extracted transaction key
  -- just because a later model response omits it. Changed bytes/version never
  -- inherit that key, and the duplicate decision uses the effective stored key.
  effective_semantic_digest := case when same_request and p_semantic_digest is null
    then prior.semantic_digest else p_semantic_digest end;

  -- Serialize equal fingerprints across different requests, including concurrent
  -- first submissions. A deterministic order avoids SHA/semantic lock inversion.
  for lock_key in
    select distinct hashtextextended(value, 161) from unnest(array[
      'sha256:' || p_sha256,
      case when effective_semantic_digest is not null then 'semantic:' || effective_semantic_digest end
    ]) value where value is not null order by 1
  loop
    perform pg_advisory_xact_lock(lock_key);
  end loop;

  select exists(select 1 from benchmark_private.oi_evidence_fingerprints
    where evidence_id <> p_evidence_id and sha256 = p_sha256) into exact_duplicate;
  select effective_semantic_digest is not null and exists(select 1 from benchmark_private.oi_evidence_fingerprints
    where evidence_id <> p_evidence_id and semantic_digest = effective_semantic_digest) into semantic_duplicate;

  insert into benchmark_private.oi_evidence_fingerprints(evidence_id, submitted_at, sha256, semantic_digest)
    values(p_evidence_id, p_submitted_at, p_sha256, effective_semantic_digest)
  on conflict(evidence_id) do update set submitted_at = excluded.submitted_at,
    sha256 = excluded.sha256, semantic_digest = excluded.semantic_digest;
  return jsonb_build_object('exact_duplicate', exact_duplicate,
    'semantic_duplicate', semantic_duplicate, 'same_request', same_request);
end;
$$;
revoke all on function benchmark_private.oi_register_evidence_fingerprint(uuid,uuid,text,timestamptz,text,text)
  from public, anon, authenticated;
grant usage on schema benchmark_private to service_role;
grant execute on function benchmark_private.oi_register_evidence_fingerprint(uuid,uuid,text,timestamptz,text,text)
  to service_role;

-- Only the server supplies digests after authenticating the user and reading the
-- current upload. Client claims and a shared SMS template are never authority.
create function public.oi_register_evidence_fingerprint(
  p_evidence_id uuid, p_user_id uuid, p_object_path text, p_submitted_at timestamptz,
  p_sha256 text, p_semantic_digest text default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select benchmark_private.oi_register_evidence_fingerprint(
    p_evidence_id, p_user_id, p_object_path, p_submitted_at, p_sha256, p_semantic_digest);
$$;
revoke all on function public.oi_register_evidence_fingerprint(uuid,uuid,text,timestamptz,text,text)
  from public, anon, authenticated;
grant execute on function public.oi_register_evidence_fingerprint(uuid,uuid,text,timestamptz,text,text)
  to service_role;

commit;

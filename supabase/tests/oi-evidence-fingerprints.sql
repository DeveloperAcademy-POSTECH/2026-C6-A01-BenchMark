begin;

create function pg_temp.assert_true(result boolean, description text) returns void
language plpgsql as $$
begin
  if result is distinct from true then raise exception 'Evidence fingerprint assertion failed: %', description; end if;
end;
$$;
create function pg_temp.assert_error(command text, expected_state text) returns void
language plpgsql as $$
begin
  begin execute command;
  exception when others then
    if sqlstate = expected_state then return; end if;
    raise exception 'Expected %, got %: %', expected_state, sqlstate, sqlerrm;
  end;
  raise exception 'Expected error % for %', expected_state, command;
end;
$$;

\set owner 'ef160000-0000-4000-8000-000000000001'
\set other 'ef160000-0000-4000-8000-000000000002'
\set owner_session 'ef160000-0000-4000-8000-000000000011'
\set other_session 'ef160000-0000-4000-8000-000000000012'
\set first 'ef160000-0000-4000-8000-000000000021'
\set same_owner_copy 'ef160000-0000-4000-8000-000000000022'
\set semantic_copy 'ef160000-0000-4000-8000-000000000023'
\set template_one 'ef160000-0000-4000-8000-000000000024'
\set template_two 'ef160000-0000-4000-8000-000000000025'
\set replacement 'ef160000-0000-4000-8000-000000000026'
\set retired_copy 'ef160000-0000-4000-8000-000000000027'
\set approved_copy 'ef160000-0000-4000-8000-000000000028'
\set invalid_path 'ef160000-0000-4000-8000-000000000029'
\set submitted '2026-11-05T00:00:00Z'

insert into auth.users(id) values (:'owner'), (:'other');
insert into auth.sessions(id,user_id) values (:'owner_session', :'owner'), (:'other_session', :'other');
insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at)
select id, owner_id, owner_id, 'pending', owner_id::text || '/' || id::text || '/synthetic.png', :'submitted'::timestamptz
from (values
  (:'first'::uuid, :'owner'::uuid), (:'same_owner_copy'::uuid, :'owner'::uuid),
  (:'semantic_copy'::uuid, :'other'::uuid), (:'template_one'::uuid, :'owner'::uuid),
  (:'template_two'::uuid, :'other'::uuid), (:'replacement'::uuid, :'owner'::uuid),
  (:'retired_copy'::uuid, :'other'::uuid), (:'approved_copy'::uuid, :'other'::uuid),
  (:'invalid_path'::uuid, :'owner'::uuid)
) fixtures(id,owner_id);

-- All values below are synthetic local Vault-stub data. Assertions return void
-- and never print decrypted key contents, including on failure.
select pg_temp.assert_true((select count(*) = 1 from vault.secrets
  where name = 'oi_evidence_fingerprint_key'), 'migration creates or reuses exactly one named HMAC key');
select vault.create_secret(repeat('d',64), 'oi_evidence_fingerprint_key_decoy', 'Synthetic decoy for exact-name lookup');
set local role service_role;
select pg_temp.assert_true(public.oi_evidence_fingerprint_key() ~ '^[0-9a-f]{64}$',
  'server can transiently retrieve the dedicated key without logging it');
select pg_temp.assert_true(public.oi_evidence_fingerprint_key() = public.oi_evidence_fingerprint_key(),
  'repeated reads reuse the stable key');
select pg_temp.assert_true(public.oi_evidence_fingerprint_key() <> repeat('d',64),
  'getter reads the exact stable secret name, never a similar secret name');
select pg_temp.assert_error('select * from vault.decrypted_secrets', '42501');
reset role;
savepoint missing_key;
delete from vault.secrets where name = 'oi_evidence_fingerprint_key';
set local role service_role;
select pg_temp.assert_error('select public.oi_evidence_fingerprint_key()', '55000');
reset role;
rollback to savepoint missing_key;
release savepoint missing_key;
savepoint malformed_key;
update vault.secrets set secret = 'invalid-synthetic-key' where name = 'oi_evidence_fingerprint_key';
set local role service_role;
select pg_temp.assert_error('select public.oi_evidence_fingerprint_key()', '55000');
reset role;
rollback to savepoint malformed_key;
release savepoint malformed_key;

select pg_temp.assert_true((select relrowsecurity from pg_class
  where oid = 'benchmark_private.oi_evidence_fingerprints'::regclass), 'private ledger enables RLS');
select pg_temp.assert_true((select array_agg(attname order by attnum) =
  array['evidence_id','submitted_at','sha256','semantic_digest']::name[]
  from pg_attribute where attrelid = 'benchmark_private.oi_evidence_fingerprints'::regclass
  and attnum > 0 and not attisdropped), 'ledger stores references and hashes, never text or donor identity');
select pg_temp.assert_true((select count(*) = 0 from pg_policy
  where polrelid = 'benchmark_private.oi_evidence_fingerprints'::regclass), 'ledger has no client RLS policies');
select pg_temp.assert_true(not has_table_privilege('service_role',
  'benchmark_private.oi_evidence_fingerprints', 'SELECT,INSERT,UPDATE,DELETE'), 'even service role uses the bounded RPC');

set local role anon;
select pg_temp.assert_error('select public.oi_evidence_fingerprint_key()', '42501');
select pg_temp.assert_error('select benchmark_private.oi_evidence_fingerprint_key()', '42501');
select pg_temp.assert_error('select * from benchmark_private.oi_evidence_fingerprints', '42501');
select pg_temp.assert_error($q$select public.oi_register_evidence_fingerprint(null,null,null,null,null)$q$, '42501');
set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_error('select public.oi_evidence_fingerprint_key()', '42501');
select pg_temp.assert_error('select benchmark_private.oi_evidence_fingerprint_key()', '42501');
select pg_temp.assert_error('select * from benchmark_private.oi_evidence_fingerprints', '42501');
select pg_temp.assert_error($q$insert into benchmark_private.oi_evidence_fingerprints values(null,null,null,null)$q$, '42501');
select pg_temp.assert_error($q$select public.oi_register_evidence_fingerprint(null,null,null,null,null)$q$, '42501');
select pg_temp.assert_error($q$select benchmark_private.oi_register_evidence_fingerprint(null,null,null,null,null)$q$, '42501');
reset role;
select pg_temp.assert_true((select count(*) = 0 from benchmark_private.oi_evidence_fingerprints),
  'forged JWT role cannot poison or read the ledger');

set local role service_role;
select public.oi_register_evidence_fingerprint(:'first', :'owner', :'owner' || '/' || :'first' || '/synthetic.png',
  :'submitted', repeat('a',64), repeat('b',64)) as initial_result \gset
select pg_temp.assert_true(:'initial_result'::jsonb =
  '{"exact_duplicate":false,"semantic_duplicate":false,"same_request":false}'::jsonb, 'first upload is not a duplicate');
select pg_temp.assert_true(public.oi_register_evidence_fingerprint(:'first', :'owner', :'owner' || '/' || :'first' || '/synthetic.png',
  :'submitted', repeat('a',64), repeat('b',64)) =
  '{"exact_duplicate":false,"semantic_duplicate":false,"same_request":true}'::jsonb, 'same request retry is idempotent');
select pg_temp.assert_true(public.oi_register_evidence_fingerprint(:'first', :'owner', :'owner' || '/' || :'first' || '/synthetic.png',
  :'submitted', repeat('a',64)) =
  '{"exact_duplicate":false,"semantic_duplicate":false,"same_request":true}'::jsonb,
  'same upload with an omitted extraction remains an idempotent retry');
reset role;
select pg_temp.assert_true((select semantic_digest = repeat('b',64)
  from benchmark_private.oi_evidence_fingerprints where evidence_id = :'first'),
  'omitted extraction preserves a previously registered transaction digest');
set local role service_role;
select pg_temp.assert_true((public.oi_register_evidence_fingerprint(:'same_owner_copy', :'owner',
  :'owner' || '/' || :'same_owner_copy' || '/synthetic.png', :'submitted', repeat('a',64)) ->> 'exact_duplicate')::boolean,
  'same account using a different request still detects exact reuse');
select pg_temp.assert_true(public.oi_register_evidence_fingerprint(:'semantic_copy', :'other',
  :'other' || '/' || :'semantic_copy' || '/synthetic.png', :'submitted', repeat('c',64), repeat('b',64)) =
  '{"exact_duplicate":false,"semantic_duplicate":true,"same_request":false}'::jsonb,
  'different accounts and different bytes detect the same trusted transaction digest');
select pg_temp.assert_true(public.oi_register_evidence_fingerprint(:'first', :'owner',
  :'owner' || '/' || :'first' || '/synthetic.png', :'submitted', repeat('a',64)) =
  '{"exact_duplicate":true,"semantic_duplicate":true,"same_request":true}'::jsonb,
  'omitted extraction checks the effective preserved key against other requests');
select pg_temp.assert_true(public.oi_register_evidence_fingerprint(:'template_one', :'owner',
  :'owner' || '/' || :'template_one' || '/synthetic.png', :'submitted', repeat('d',64)) =
  '{"exact_duplicate":false,"semantic_duplicate":false,"same_request":false}'::jsonb, 'template with no transaction key is not semantic evidence');
select pg_temp.assert_true(public.oi_register_evidence_fingerprint(:'template_two', :'other',
  :'other' || '/' || :'template_two' || '/synthetic.png', :'submitted', repeat('e',64)) =
  '{"exact_duplicate":false,"semantic_duplicate":false,"same_request":false}'::jsonb, 'another copy of a shared template is not inferred duplicate');

select pg_temp.assert_error(format('select public.oi_register_evidence_fingerprint(%L,%L,%L,%L,%L)',
  :'first', :'other', :'owner' || '/' || :'first' || '/synthetic.png', :'submitted', repeat('a',64)), '40001');
select pg_temp.assert_error(format('select public.oi_register_evidence_fingerprint(%L,%L,%L,%L,%L)',
  :'first', :'owner', :'owner' || '/' || :'first' || '/replacement.png', :'submitted', repeat('a',64)), '40001');
select pg_temp.assert_error(format('select public.oi_register_evidence_fingerprint(%L,%L,%L,%L,%L)',
  :'first', :'owner', :'owner' || '/' || :'first' || '/synthetic.png', '2026-11-05T00:01:00Z', repeat('a',64)), '40001');
select pg_temp.assert_error(format('select public.oi_register_evidence_fingerprint(%L,%L,%L,%L,%L)',
  :'first', :'owner', :'owner' || '/' || :'first' || '/synthetic.png', :'submitted', 'not-a-hash'), '22023');
select pg_temp.assert_error(format('select public.oi_register_evidence_fingerprint(%L,%L,%L,%L,%L,%L)',
  :'first', :'owner', :'owner' || '/' || :'first' || '/synthetic.png', :'submitted', repeat('a',64), 'raw donor detail'), '22023');
select pg_temp.assert_error('select public.oi_register_evidence_fingerprint(null,null,null,null,null)', '22023');

select public.oi_register_evidence_fingerprint(:'replacement', :'owner', :'owner' || '/' || :'replacement' || '/synthetic.png',
  :'submitted', repeat('1',64), repeat('2',64));
reset role;
update public.oi_evidence_requests set object_path = :'owner' || '/' || :'replacement' || '/replacement.png',
  submitted_at = '2026-11-05T00:01:00Z' where id = :'replacement';
select pg_temp.assert_true(not exists(select 1 from benchmark_private.oi_evidence_fingerprints where evidence_id = :'replacement'),
  'replacement immediately retires the previous fingerprint before reanalysis');
set local role service_role;
select pg_temp.assert_true(public.oi_register_evidence_fingerprint(:'retired_copy', :'other',
  :'other' || '/' || :'retired_copy' || '/synthetic.png', :'submitted', repeat('1',64), repeat('2',64)) =
  '{"exact_duplicate":false,"semantic_duplicate":false,"same_request":false}'::jsonb, 'retired upload does not falsely mark later evidence');
select public.oi_register_evidence_fingerprint(:'replacement', :'owner', :'owner' || '/' || :'replacement' || '/replacement.png',
  '2026-11-05T00:01:00Z', repeat('3',64), repeat('4',64));
-- A changed byte digest at the same submission version must not inherit a key.
select pg_temp.assert_true((public.oi_register_evidence_fingerprint(:'replacement', :'owner',
  :'owner' || '/' || :'replacement' || '/replacement.png', '2026-11-05T00:01:00Z', repeat('5',64)) ->> 'same_request')::boolean is false,
  'different bytes are not an unchanged-upload retry');
reset role;
select pg_temp.assert_true((select semantic_digest is null from benchmark_private.oi_evidence_fingerprints
  where evidence_id = :'replacement'), 'different bytes never inherit the previous transaction digest');
-- Even identical bytes in a new version must not inherit the prior version key.
set local role service_role;
select public.oi_register_evidence_fingerprint(:'replacement', :'owner', :'owner' || '/' || :'replacement' || '/replacement.png',
  '2026-11-05T00:01:00Z', repeat('5',64), repeat('6',64));
reset role;
update public.oi_evidence_requests set submitted_at = '2026-11-05T00:02:00Z' where id = :'replacement';
set local role service_role;
select pg_temp.assert_true((public.oi_register_evidence_fingerprint(:'replacement', :'owner',
  :'owner' || '/' || :'replacement' || '/replacement.png', '2026-11-05T00:02:00Z', repeat('5',64)) ->> 'same_request')::boolean is false,
  'new submission version is not an unchanged-upload retry');
reset role;
select pg_temp.assert_true((select semantic_digest is null from benchmark_private.oi_evidence_fingerprints
  where evidence_id = :'replacement'), 'new submission versions never inherit the previous transaction digest');
update public.oi_evidence_requests set status = 'approved' where id = :'first';
set local role service_role;
select pg_temp.assert_true((public.oi_register_evidence_fingerprint(:'approved_copy', :'other',
  :'other' || '/' || :'approved_copy' || '/synthetic.png', :'submitted', repeat('a',64)) ->> 'exact_duplicate')::boolean,
  'reviewing a request does not remove its duplicate history');
select pg_temp.assert_error(format('select public.oi_register_evidence_fingerprint(%L,%L,%L,%L,%L)',
  :'first', :'owner', :'owner' || '/' || :'first' || '/synthetic.png', :'submitted', repeat('a',64)), '40001');
reset role;
update public.oi_evidence_requests set object_path = :'owner' || '/' || :'invalid_path' || '/../unexpected.png' where id = :'invalid_path';
set local role service_role;
select pg_temp.assert_error(format('select public.oi_register_evidence_fingerprint(%L,%L,%L,%L,%L)',
  :'invalid_path', :'owner', :'owner' || '/' || :'invalid_path' || '/../unexpected.png', :'submitted', repeat('a',64)), '22023');

select public.oi_merge_accounts('preview', 'ef160000-0000-4000-8000-000000000051',
  :'owner', :'other', :'owner_session', :'other_session') as merge_preview \gset
select public.oi_merge_accounts('confirm', 'ef160000-0000-4000-8000-000000000051',
  :'owner', :'other', :'owner_session', :'other_session', (:'merge_preview'::jsonb ->> 'challenge_id')::uuid, true);
reset role;
select pg_temp.assert_true((select user_id = :'owner' and storage_owner_id = :'other'
  from public.oi_evidence_requests where id = :'semantic_copy'), 'merge changes the canonical owner while preserving Storage owner');
select pg_temp.assert_true(exists(select 1 from benchmark_private.oi_evidence_fingerprints where evidence_id = :'semantic_copy'),
  'merge preserves the request-owned ledger without a private ledger rewrite');
set local role service_role;
select pg_temp.assert_error(format('select public.oi_register_evidence_fingerprint(%L,%L,%L,%L,%L)',
  :'semantic_copy', :'other', :'other' || '/' || :'semantic_copy' || '/synthetic.png', :'submitted', repeat('c',64)), '40001');
select pg_temp.assert_true((public.oi_register_evidence_fingerprint(:'semantic_copy', :'owner',
  :'other' || '/' || :'semantic_copy' || '/synthetic.png', :'submitted', repeat('c',64), repeat('b',64)) ->> 'same_request')::boolean,
  'merged canonical owner can retry the original Storage upload idempotently');
reset role;
delete from public.oi_evidence_requests where id = :'template_one';
select pg_temp.assert_true(not exists(select 1 from benchmark_private.oi_evidence_fingerprints where evidence_id = :'template_one'),
  'request deletion cascades its fingerprint');

rollback;

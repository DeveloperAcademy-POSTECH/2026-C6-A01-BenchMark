#!/usr/bin/env python3
"""Run migration and ownership tests in a task-owned, Unix-socket-only PostgreSQL."""
import json
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPOSITORY = Path(__file__).resolve().parents[2]
TEMPORARY_BASE = Path('/private/tmp') if Path('/private/tmp').is_dir() else Path(tempfile.gettempdir()).resolve()
PREFIX = str(TEMPORARY_BASE / 'account-merge-124-')
rows = subprocess.run(['ps', '-axo', 'command='], capture_output=True, text=True, check=True).stdout.splitlines()
if any('postgres -D ' + PREFIX in row for row in rows):
    raise SystemExit('An account merge test database is already running. Inspect its runtime registry before retrying.')
for name in ['initdb', 'pg_ctl', 'psql']:
    if shutil.which(name) is None:
        raise SystemExit(f'Install/provide PostgreSQL tools before running this check: {name}')
root = Path(tempfile.mkdtemp(prefix='account-merge-124-', dir=TEMPORARY_BASE))
root.chmod(0o700)
socket = root / 'socket'
socket.mkdir(mode=0o700)
data = root / 'data'
port = '55424'
registry = {'purpose': 'Account merge database regression checks', 'maximumConcurrentGroups': 1, 'resources': []}
registry_path = root / 'runtime-registry.json'
log_path = root / 'checks.log'
started = False
succeeded = False

def run(command, **options):
    result = subprocess.run(command, cwd=REPOSITORY, stdout=log, stderr=subprocess.STDOUT, timeout=30, **options)
    if result.returncode:
        log.flush()
        raise RuntimeError(f'Check failed (exit {result.returncode}): {command[0]}\n{log_path.read_text()[-3000:]}')
    return result

def check_postcard_cover_drift(connection, migration):
    def query(sql):
        return subprocess.run(connection + ['-qAtc', sql], capture_output=True, text=True, check=True, timeout=20).stdout.strip()

    # Catalog state must survive a failure even after constraint/policy/parts edits
    # and, for capability drift, the mutation function patch have already executed.
    catalog = """select jsonb_build_object(
      'mutate',pg_get_functiondef('benchmark_private.oi_mutate(text,jsonb)'::regprocedure),
      'capabilities',pg_get_functiondef('public.oi_capabilities()'::regprocedure),
      'parts',pg_get_functiondef('benchmark_private.oi_story_card_parts(uuid,uuid,uuid,integer)'::regprocedure),
      'checks',(select jsonb_agg(pg_get_constraintdef(oid) order by conname) from pg_constraint
        where conrelid='public.oi_stories'::regclass and contype='c'),
      'policy',(select pg_get_expr(polqual,polrelid) from pg_policy
        where polrelid='storage.objects'::regclass and polname='oi_duplex_story_card_read'));"""
    patches = [
        ('benchmark_private.oi_mutate(text,jsonb)', 'oi_mutate', 'if story.card_snapshot_format not in (1,2) then'),
        ('benchmark_private.oi_mutate(text,jsonb)', 'oi_mutate',
         "(story.card_snapshot_format=2 and coalesce(payload->>'card_snapshot_format','')<>'2')"),
        ('public.oi_capabilities()', 'oi_capabilities', "'duplex_story_card',true"),
    ]
    for signature, name, anchor in patches:
        definition = query(f"select pg_get_functiondef('{signature}'::regprocedure);")
        assert definition.count(anchor) == 1
        for duplicate in (False, True):
            changed = anchor + f' /* {anchor} */' if duplicate else anchor.replace(',', ', ', 1)
            run(connection, input=definition.replace(anchor, changed), text=True)
            before = query(catalog)
            try:
                rejected = subprocess.run(connection + ['-f', str(migration)], capture_output=True, text=True, timeout=20)
                assert rejected.returncode != 0 and f'{name} drift requires postcard cover review' in rejected.stderr, rejected.stderr
                assert query(catalog) == before, 'Postcard cover migration did not roll back completely'
            finally:
                run(connection, input=definition, text=True)
    print('PASS: postcard cover rejects missing/duplicate mutation and capability anchors; all six failures roll back')

def jpeg_cover_catalog(connection):
    sql = """select jsonb_build_object(
      'functions',(select jsonb_agg(jsonb_build_object('definition',pg_get_functiondef(oid),
        'acl',proacl) order by oid) from pg_proc where pronamespace='benchmark_private'::regnamespace
        and proname in ('oi_mutate','oi_check_story_card','oi_story_card_parts')),
      'capabilities',pg_get_functiondef('public.oi_capabilities()'::regprocedure),
      'columns',(select jsonb_agg(attname order by attnum) from pg_attribute
        where attrelid='public.oi_stories'::regclass and attnum>0 and not attisdropped),
      'checks',(select jsonb_agg(pg_get_constraintdef(oid) order by conname) from pg_constraint
        where conrelid='public.oi_stories'::regclass and contype='c'),
      'policy',(select pg_get_expr(polqual,polrelid) from pg_policy
        where polrelid='storage.objects'::regclass and polname='oi_duplex_story_card_read'),
      'rows',(select jsonb_agg(to_jsonb(s) order by id) from public.oi_stories s where id::text like 'c349%'));"""
    return subprocess.run(connection + ['-qAtc', sql], capture_output=True, text=True, check=True, timeout=20).stdout.strip()


def check_jpeg_cover_drift(connection, migration):
    # Exercise every actual replacement anchor, including multi-line mutation patches.
    # Whitespace drift preserves the function's behavior but must fail the migration.
    anchors = re.findall(r'\$old\$([\s\S]*?)\$old\$', migration.read_text())
    assert len(anchors) == 6
    patches = [('benchmark_private.oi_check_story_card(public.oi_stories)', anchor) for anchor in anchors[:3]]
    patches += [('benchmark_private.oi_mutate(text,jsonb)', anchor) for anchor in anchors[3:]]
    patches += [('public.oi_capabilities()', "'story_card_cover',true")]
    for signature, anchor in patches:
        definition = subprocess.run(connection + ['-qAtc', f"select pg_get_functiondef('{signature}'::regprocedure);"],
                                    capture_output=True, text=True, check=True, timeout=20).stdout.strip()
        assert definition.count(anchor) == 1, signature
        for duplicate in (False, True):
            body = anchor.lstrip()
            changed = anchor + f' /* {anchor} */' if duplicate else anchor[:len(anchor)-len(body)] + (
                body.replace(',', ', ', 1) if ',' in body else body.replace(' ', '  ', 1))
            run(connection, input=definition.replace(anchor, changed), text=True)
            before = jpeg_cover_catalog(connection)
            try:
                rejected = subprocess.run(connection + ['-f', str(migration)], capture_output=True, text=True, timeout=20)
                assert rejected.returncode != 0 and 'drift requires JPEG cover review' in rejected.stderr, (signature, duplicate, rejected.returncode, rejected.stderr)
                assert jpeg_cover_catalog(connection) == before, 'JPEG migration did not roll back data, schema, functions, grants and policy'
            finally:
                run(connection, input=definition, text=True)
    print('PASS: all 14 JPEG anchor drift failures roll back schema, backfill, functions, grants and policy')


def seed_jpeg_cover_backfill(connection):
    owner = 'c3490000-0000-4000-8000-000000000001'
    run(connection, input=f"insert into auth.users(id) values('{owner}');", text=True)
    for index, (format, status) in enumerate([(1,'draft'), (2,'published'), (3,'draft'), (3,'pending'), (3,'published'), (3,'hidden'), (3,'deleted')], 11):
        story = f'c3490000-0000-4000-8000-{index:012d}'
        snapshot = 'null' if format == 1 else "'c3490000-0000-4000-8000-000000000031'::uuid"
        run(connection, input=f"""insert into public.oi_stories(id,user_id,storage_owner_id,region_id,title,body,theme,emotion,
          cucumber_name,cucumber_asset,card_asset,latitude,longitude,status,revision,card_snapshot_id,card_snapshot_format)
          values('{story}','{owner}','{owner}','pond','Synthetic backfill','Body','theme','emotion','one','OiCats','MYBasicCard',36,129,
          '{status}',7,{snapshot},{format});""", text=True)
    sql = "select jsonb_agg(to_jsonb(s) order by id) from public.oi_stories s where id::text like 'c349%';"
    return subprocess.run(connection + ['-qAtc', sql], capture_output=True, text=True, check=True, timeout=20).stdout.strip()


def check_jpeg_cover_backfill(connection, before):
    sql = "select jsonb_agg(to_jsonb(s)-'card_cover_type' order by id) from public.oi_stories s where id::text like 'c349%';"
    after = subprocess.run(connection + ['-qAtc', sql], capture_output=True, text=True, check=True, timeout=20).stdout.strip()
    assert json.loads(before) == json.loads(after), 'PNG backfill changed existing story data or revision'
    run(connection, input="""do $$ begin
      if exists(select 1 from public.oi_stories where id::text like 'c349%' and
        ((card_snapshot_format=3 and card_cover_type is distinct from 'png')
          or (card_snapshot_format in (1,2) and card_cover_type is not null))) then
        raise exception 'Incorrect legacy cover type backfill';
      end if;
    end; $$;
    delete from public.oi_stories where id::text like 'c349%';
    delete from benchmark_private.oi_account_members where auth_user_id='c3490000-0000-4000-8000-000000000001';
    delete from public.oi_profiles where id='c3490000-0000-4000-8000-000000000001';
    delete from auth.users where id='c3490000-0000-4000-8000-000000000001';""", text=True)
    print('PASS: PNG backfill preserves every existing story field/revision across all five statuses and formats 1/2')


def check_fingerprint_concurrency(connection):
    # Both requests enter before either commits. Equal SHA or transaction digests
    # must serialize, so exactly one caller observes the newly registered peer.
    users = ['ef169000-0000-4000-8000-000000000001', 'ef169000-0000-4000-8000-000000000002']
    run(connection, input="insert into auth.users(id) values('" + users[0] + "'),('" + users[1] + "');", text=True)
    for scenario in ['exact', 'semantic']:
        suffixes = ['21', '22'] if scenario == 'exact' else ['31', '32']
        requests = ['ef169000-0000-4000-8000-0000000000' + suffix for suffix in suffixes]
        commands = []
        for index in [0, 1]:
            owner, request = users[index], requests[index]
            path = f'{owner}/{request}/synthetic.png'
            run(connection, input=f"insert into public.oi_evidence_requests(id,user_id,storage_owner_id,status,object_path,submitted_at) "
                f"values('{request}','{owner}','{owner}','pending','{path}','2026-11-05T00:00:00Z');", text=True)
            sha = '5' * 64 if scenario == 'exact' else str(6 + index) * 64
            semantic = 'null' if scenario == 'exact' else "'" + '8' * 64 + "'"
            command = f"begin; set local role service_role; select public.oi_register_evidence_fingerprint(" \
                f"'{request}','{owner}','{path}','2026-11-05T00:00:00Z','{sha}',{semantic}); select pg_sleep(0.2); commit;"
            commands.append(connection + ['-qAtc', command])
        processes = []
        try:
            for command in commands:
                processes.append(subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            registry['resources'][0]['clientPIDs'] = [process.pid for process in processes]
            registry_path.write_text(json.dumps(registry, indent=2))
            output = [process.communicate(timeout=20) for process in processes]
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=3)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
            registry['resources'][0]['clientPIDs'] = []
            registry_path.write_text(json.dumps(registry, indent=2))
        assert all(process.returncode == 0 for process in processes), output
        results = [json.loads(next(line for line in stdout.splitlines() if line.startswith('{'))) for stdout, _ in output]
        key = 'exact_duplicate' if scenario == 'exact' else 'semantic_duplicate'
        assert sorted(result[key] for result in results) == [False, True], results
        assert all(result['same_request'] is False for result in results), results
    print('PASS: simultaneous exact and transaction-fingerprint registrations serialize across accounts')

try:
    with log_path.open('w') as log:
        run(['initdb', '-D', str(data), '-A', 'trust', '-U', 'postgres', '--no-locale', '-E', 'UTF8'])
        run(['pg_ctl', '-D', str(data), '-l', str(root / 'postgres.log'), '-o', f"-F -h '' -k {socket} -p {port}", '-w', '-t', '20', 'start'])
        started = True
        pid = int((data / 'postmaster.pid').read_text().splitlines()[0])
        registry['resources'].append({'pid': pid, 'dataDirectory': str(data), 'socket': str(socket), 'port': port,
            'command': f"postgres -D {data} -F -h '' -k {socket} -p {port}", 'started': time.time(), 'state': 'running',
            'shutdown': ['pg_ctl', '-D', str(data), '-m', 'fast', '-w', 'stop']})
        registry_path.write_text(json.dumps(registry, indent=2))
        connection = ['psql', '-X', '-h', str(socket), '-p', port, '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
        actual = subprocess.run(connection + ['-qAtc', 'show data_directory'], capture_output=True, text=True, check=True).stdout.strip()
        assert Path(actual).resolve() == data.resolve()
        run(connection + ['-f', 'supabase/tests/bootstrap-local.sql'])
        run(connection, input="""create role service_role nologin bypassrls;
alter table auth.users add column created_at timestamptz not null default now();
create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create table auth.identities(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,provider text not null,provider_id text);
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb; $$;
grant execute on function auth.jwt() to anon,authenticated;
""", text=True)
        migrations = sorted((REPOSITORY / 'supabase/migrations').glob('*.sql'))
        independent_creation = next(path for path in migrations if path.name.endswith('_oi_independent_story_creation.sql'))
        retirement = next(path for path in migrations if path.name.endswith('_oi_retire_donation_evidence.sql'))
        # Exercise historical evidence workflows at the schema where they were available.
        post_retirement = migrations[migrations.index(retirement):]
        legacy_writing_tests = ('oi-operator-evidence', 'oi-operator-workflow', 'oi-unapproved-drafts')
        for migration in migrations:
            if migration == retirement: break
            if migration.name.endswith('_oi_independent_farm_name.sql'):
                run(connection, input="insert into auth.users(id) values('f1580000-0000-4000-8000-000000000001'); update public.oi_profiles set nickname='Legacy nickname' where id='f1580000-0000-4000-8000-000000000001';", text=True)
            if migration == independent_creation:
                for test in ('oi-flow', *legacy_writing_tests):
                    run(connection + ['-f', f'supabase/tests/{test}.sql'])
            run(connection + ['-f', str(migration)])
        run(connection + ['-f', 'supabase/tests/oi-farm-name.sql'])
        # The backfill fixture belongs only to the farm migration test.
        run(connection, input="delete from benchmark_private.oi_account_members where auth_user_id='f1580000-0000-4000-8000-000000000001' and account_id=auth_user_id; delete from auth.users where id='f1580000-0000-4000-8000-000000000001';", text=True)
        run(connection + ['-f', 'supabase/tests/oi-independent-story-creation.sql'])
        run(connection + ['-f', 'supabase/tests/oi-public-cucumber-appearance.sql'])
        run(connection + ['-f', 'supabase/tests/account-merge.sql'])
        run(connection + ['-f', 'supabase/tests/oi-card-requests.sql'])
        run(connection + ['-f', 'supabase/tests/oi-operator-audit.sql'])
        run(connection + ['-f', 'supabase/tests/oi-content-safety.sql'])
        run(connection + ['-f', 'supabase/tests/oi-school-profile.sql'])
        run(connection + ['-f', 'supabase/tests/oi-farmer-outfit.sql'])
        run(connection + ['-f', 'supabase/tests/oi-evidence-fingerprints.sql'])
        run(connection + ['-f', 'supabase/tests/oi-evidence-operator-ai-consent.sql'])
        check_fingerprint_concurrency(connection)
        print('PASS: migrations, existing SQL regression, data union, preservation, consent, operator exclusion, rollback, RLS and old-session cutover')

        users = ['90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000002']
        sessions = ['90000000-0000-4000-8000-000000000011', '90000000-0000-4000-8000-000000000012']
        operations = ['91000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000002']
        run(connection, input=f"insert into auth.users(id) values('{users[0]}'),('{users[1]}');\ninsert into auth.sessions(id,user_id) values('{sessions[0]}','{users[0]}'),('{sessions[1]}','{users[1]}');", text=True)
        commands = []
        for index in [0, 1]:
            other = 1 - index
            args = f"'{operations[index]}','{users[index]}','{users[other]}','{sessions[index]}','{sessions[other]}'"
            preview = subprocess.run(connection + ['-qAtc', f"set role service_role; select public.oi_merge_accounts('preview',{args});"], capture_output=True, text=True, check=True, timeout=10)
            challenge = json.loads(preview.stdout)['challenge_id']
            commands.append(connection + ['-qAtc', f"set role service_role; select public.oi_merge_accounts('confirm',{args},'{challenge}',true);"])
        processes = []
        try:
            for command in commands:
                processes.append(subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            registry['resources'][0]['clientPIDs'] = [process.pid for process in processes]
            registry_path.write_text(json.dumps(registry, indent=2))
            results = [process.communicate(timeout=20) for process in processes]
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=3)
                    except subprocess.TimeoutExpired: process.kill(); process.wait()
        assert sorted(process.returncode for process in processes) == [0, 1], results
        failed = next(result[1] for process, result in zip(processes, results) if process.returncode)
        assert 'accounts_already_unified' in failed, failed
        count = subprocess.run(connection + ['-qAtc', f"select count(distinct account_id) from benchmark_private.oi_account_members where auth_user_id in('{users[0]}','{users[1]}');"], capture_output=True, text=True, check=True).stdout.strip()
        assert count == '1'
        print('PASS: opposing simultaneous merges serialize; one succeeds, the other reports conflict without cycles')
        # Recreate the audited deployed schema/function variant in another database on this same task-owned server.
        run(connection + ['-c', 'create database remote_compatibility'])
        remote_connection = connection.copy()
        remote_connection[remote_connection.index('-d') + 1] = 'remote_compatibility'
        bootstrap = (REPOSITORY / 'supabase/tests/bootstrap-local.sql').read_text().replace('create role anon nologin;', '').replace('create role authenticated nologin;', '')
        run(remote_connection, input=bootstrap, text=True)
        extra = """alter table auth.users add column created_at timestamptz not null default now();
create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,created_at timestamptz not null default now());
create table auth.identities(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,provider text not null,provider_id text);
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb; $$;
grant execute on function auth.jwt() to anon,authenticated;
"""
        run(remote_connection, input=extra, text=True)
        merge_migration = next(path for path in migrations if path.name.endswith('_oi_account_merge.sql'))
        for migration in migrations:
            if migration == retirement: break
            if migration == merge_migration:
                run(remote_connection + ['-f', 'supabase/tests/fixtures/deployed-campus-mutate.sql'])
            if migration.name.endswith('_oi_evidence_fingerprints.sql'):
                # Synthetic pre-existing Vault-stub secret proves migration reuse.
                # PERFORM returns no plaintext key to the test log.
                run(remote_connection, input="do $$ begin perform vault.create_secret(repeat('c',64), 'oi_evidence_fingerprint_key', 'Synthetic pre-existing key fixture'); end; $$;", text=True)
            if migration.name.endswith('_oi_independent_farm_name.sql'):
                run(remote_connection, input="insert into auth.users(id) values('f1580000-0000-4000-8000-000000000001'); update public.oi_profiles set nickname='Legacy nickname' where id='f1580000-0000-4000-8000-000000000001';", text=True)
            if migration == independent_creation:
                for test in legacy_writing_tests:
                    run(remote_connection + ['-f', f'supabase/tests/{test}.sql'])
            run(remote_connection + ['-f', str(migration)])
        run(remote_connection + ['-f', 'supabase/tests/oi-farm-name.sql'])
        run(remote_connection, input="delete from benchmark_private.oi_account_members where auth_user_id='f1580000-0000-4000-8000-000000000001' and account_id=auth_user_id; delete from auth.users where id='f1580000-0000-4000-8000-000000000001';", text=True)
        run(remote_connection + ['-f', 'supabase/tests/account-merge.sql'])
        run(remote_connection + ['-f', 'supabase/tests/account-merge-campus-compat.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-independent-story-creation.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-public-cucumber-appearance.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-card-requests.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-operator-audit.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-school-profile.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-farmer-outfit.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-evidence-fingerprints.sql'])
        run(remote_connection, input="set role service_role; do $$ begin if public.oi_evidence_fingerprint_key() <> repeat('c',64) then raise exception 'Migration must preserve the pre-existing named key'; end if; end; $$;", text=True)
        print('PASS: deployed save_campus_story, height_meters and heading_degrees behavior survives canonical ownership patch')
        for database in (connection, remote_connection):
            for migration in post_retirement:
                if database is connection and migration.name.endswith('_oi_postcard_cover.sql'):
                    check_postcard_cover_drift(database, migration)
                if migration.name.endswith('_oi_postcard_cover_jpeg.sql'):
                    backfill_before = seed_jpeg_cover_backfill(database)
                    check_jpeg_cover_drift(database, migration)
                run(database + ['-f', str(migration)])
                if migration.name.endswith('_oi_postcard_cover_jpeg.sql'):
                    check_jpeg_cover_backfill(database, backfill_before)
            run(database + ['-f', 'supabase/tests/oi-donation-evidence-retired.sql'])
            run(database + ['-f', 'supabase/tests/oi-account-deletion.sql'])
            run(database + ['-f', 'supabase/tests/oi-bounded-collection-metrics.sql'])
            run(database + ['-f', 'supabase/tests/oi-nfc-postcard-tags.sql'])

            run(database + ['-f', 'supabase/tests/oi-duplex-story-card.sql'])
            run(database + ['-f', 'supabase/tests/oi-postcard-cover.sql'])
            run(database + ['-f', 'supabase/tests/oi-postcard-cover-jpeg.sql'])
            run(database + ['-f', 'supabase/tests/oi-education-stories.sql'])
            run(database + ['-f', 'supabase/tests/oi-education-reference-catalog.sql'])
            run(database + ['-f', 'supabase/tests/oi-public-cucumber-appearance.sql'])
            run(database + ['-f', 'supabase/tests/oi-building-notes.sql'])
            run(database + ['-f', 'supabase/tests/oi-building-note-moderation.sql'])
        print('PASS: card formats 1/2/3, PNG/JPEG cover validation/access/review, and deletion on both histories')
        print('PASS: building notes writes, reports, AI/operator review, pagination, merge and deletion on both histories')
        print('PASS: retired evidence RPCs and uploads, retained private records and deletion, story moderation on both histories')
        # Unknown owning function edits must stop the migration before any schema change commits.
        run(connection + ['-c', 'create database unknown_drift'])
        drift_connection = connection.copy()
        drift_connection[drift_connection.index('-d') + 1] = 'unknown_drift'
        run(drift_connection, input=bootstrap, text=True)
        run(drift_connection, input=extra, text=True)
        for migration in migrations:
            if migration == merge_migration: break
            run(drift_connection + ['-f', str(migration)])
        run(drift_connection, input="create or replace function benchmark_private.oi_mutate(action text,payload jsonb) returns jsonb language plpgsql as $$ begin return '{}'::jsonb; end; $$;", text=True)
        rejected = subprocess.run(drift_connection + ['-f', str(merge_migration)], capture_output=True, text=True, timeout=20)
        assert rejected.returncode != 0 and 'drift requires an ownership review' in rejected.stderr
        absent = subprocess.run(drift_connection + ['-qAtc', "select to_regclass('benchmark_private.oi_account_members') is null;"], capture_output=True, text=True, check=True).stdout.strip()
        assert absent == 't'
        print('PASS: unknown owning RPC drift rejects and rolls back the entire migration')
        # The temporary-writing migration must also reject unknown deployed RPC changes.
        run(connection + ['-c', 'create database temporary_writing_drift'])
        writing_connection = connection.copy()
        writing_connection[writing_connection.index('-d') + 1] = 'temporary_writing_drift'
        run(writing_connection, input=bootstrap, text=True)
        run(writing_connection, input=extra, text=True)
        writing_migration = next(path for path in migrations if path.name.endswith('_oi_temporary_story_drafts.sql'))
        for migration in migrations:
            if migration == writing_migration: break
            run(writing_connection + ['-f', str(migration)])
        run(writing_connection, input="create or replace function benchmark_private.oi_mutate(action text,payload jsonb) returns jsonb language plpgsql as $$ begin return '{}'::jsonb; end; $$;", text=True)
        rejected = subprocess.run(writing_connection + ['-f', str(writing_migration)], capture_output=True, text=True, timeout=20)
        assert rejected.returncode != 0 and 'drift requires review before temporary writing' in rejected.stderr
        intact = subprocess.run(writing_connection + ['-qAtc', "select to_regclass('benchmark_private.oi_story_creation_settings') is null and (select attnotnull from pg_attribute where attrelid='public.oi_stories'::regclass and attname='grant_id');"], capture_output=True, text=True, check=True).stdout.strip()
        assert intact == 't'
        print('PASS: temporary draft mode ON/OFF, private media retention, approval quota/revocation, and unknown RPC rollback')
        succeeded = True
finally:
    # pg_ctl can time out after starting the server, so inspect the task-owned PID file as well.
    if started or (data / 'postmaster.pid').exists():
        if (data / 'postmaster.pid').exists():
            lines = (data / 'postmaster.pid').read_text().splitlines()
            assert Path(lines[1]).resolve() == data.resolve()
            if not registry['resources']:
                registry['resources'].append({'pid': int(lines[0]), 'dataDirectory': str(data), 'socket': str(socket)})
        stopped = subprocess.run(['pg_ctl', '-D', str(data), '-m', 'fast', '-w', '-t', '20', 'stop'], capture_output=True, text=True, timeout=25)
        if stopped.returncode:
            raise RuntimeError(f'Task database cleanup failed. Inspect {registry_path}')
        assert not (data / 'postmaster.pid').exists()
        assert not (socket / f'.s.PGSQL.{port}').exists()
        registry['resources'][0]['state'] = 'stopped'
        registry['cleanupVerified'] = True
        registry_path.write_text(json.dumps(registry, indent=2))
        print('PASS: task-owned PostgreSQL stopped; PID file and socket removed')
    if succeeded:
        shutil.rmtree(root)
        assert not root.exists()
    else:
        print(f'Failure artifacts retained at {root}; no task database remains running' if started else f'Failure artifacts: {root}')

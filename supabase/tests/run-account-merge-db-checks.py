#!/usr/bin/env python3
"""Run migration and ownership tests in a task-owned, Unix-socket-only PostgreSQL."""
import json
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

try:
    with log_path.open('w') as log:
        run(['initdb', '-D', str(data), '-A', 'trust', '-U', 'postgres', '--no-locale'])
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
create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id),created_at timestamptz not null default now());
create table auth.identities(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),provider text not null);
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb; $$;
grant execute on function auth.jwt() to anon,authenticated;
""", text=True)
        for migration in sorted((REPOSITORY / 'supabase/migrations').glob('*.sql')):
            run(connection + ['-f', str(migration)])
        run(connection + ['-f', 'supabase/tests/oi-flow.sql'])
        run(connection + ['-f', 'supabase/tests/account-merge.sql'])
        run(connection + ['-f', 'supabase/tests/oi-card-requests.sql'])
        run(connection + ['-f', 'supabase/tests/oi-operator-evidence.sql'])
        run(connection + ['-f', 'supabase/tests/oi-operator-audit.sql'])
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
create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id),created_at timestamptz not null default now());
create table auth.identities(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),provider text not null);
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb; $$;
grant execute on function auth.jwt() to anon,authenticated;
"""
        run(remote_connection, input=extra, text=True)
        migrations = sorted((REPOSITORY / 'supabase/migrations').glob('*.sql'))
        merge_migration = next(path for path in migrations if path.name.endswith('_oi_account_merge.sql'))
        for migration in migrations:
            if migration == merge_migration:
                run(remote_connection + ['-f', 'supabase/tests/fixtures/deployed-campus-mutate.sql'])
            run(remote_connection + ['-f', str(migration)])
        run(remote_connection + ['-f', 'supabase/tests/account-merge.sql'])
        run(remote_connection + ['-f', 'supabase/tests/account-merge-campus-compat.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-card-requests.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-operator-evidence.sql'])
        run(remote_connection + ['-f', 'supabase/tests/oi-operator-audit.sql'])
        print('PASS: deployed save_campus_story, height_meters and heading_degrees behavior survives canonical ownership patch')
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

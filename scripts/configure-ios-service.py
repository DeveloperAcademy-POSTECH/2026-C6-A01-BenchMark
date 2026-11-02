#!/usr/bin/env python3
"""Provision only a public client key; never write credentials to tracked files."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--from-cli', action='store_true')
parser.add_argument('--http-check', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
key = os.environ.get('OI_SUPABASE_PUBLISHABLE_KEY', '')
if args.from_cli:
    result = subprocess.run(['supabase', 'projects', 'api-keys', '--project-ref', 'kfzfzarslqdqmrazohej', '-o', 'json'], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('Supabase key lookup failed. Verify CLI identity and project access.')
    records = json.loads(result.stdout)
    if isinstance(records, dict):
        records = records.get('keys', [])
    key = next((r['api_key'] for r in records if r.get('name') == 'anon' and not r.get('disabled')), '')
if key.startswith('ey'):
    payload = key.split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
    if claims.get('role') != 'anon' or claims.get('ref') != 'kfzfzarslqdqmrazohej':
        raise SystemExit('Wrong project or privileged key rejected.')
elif not key.startswith('sb_publishable_'):
    raise SystemExit('Set OI_SUPABASE_PUBLISHABLE_KEY to a public client key.')
if any(c.isspace() for c in key):
    raise SystemExit('Invalid public key.')
for app in ['OiDonation', 'OiDonationClip']:
    path = root / 'apps' / 'ios' / app / 'Service.local.plist'
    data = plistlib.dumps({'publishableKey': key})
    if path.exists() and path.read_bytes() != data:
        raise SystemExit(f'Existing local configuration differs: {path}')
    path.write_bytes(data)
    path.chmod(0o600)
print('Configured 52gibu public client key in ignored local app resources.')
if args.http_check:
    subprocess.run(['python3', str(root / 'supabase/tests/http-smoke.py')], env={**os.environ, 'OI_SUPABASE_PUBLISHABLE_KEY': key}, check=True)

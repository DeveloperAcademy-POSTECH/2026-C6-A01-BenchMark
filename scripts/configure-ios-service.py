#!/usr/bin/env python3
"""Provision only a public client key; never write credentials to tracked files."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
from xml.parsers.expat import ExpatError


def validate_key(key):
    if not isinstance(key, str) or re.fullmatch(r'[A-Za-z0-9_.-]+', key) is None:
        raise ValueError('A valid public client key is required.')
    if key.startswith('ey'):
        try:
            parts = key.split('.')
            if len(parts) != 3:
                raise ValueError()
            payload = parts[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
            if claims.get('role') != 'anon' or claims.get('ref') != 'kfzfzarslqdqmrazohej':
                raise ValueError()
        except (ValueError, TypeError, AttributeError):
            raise ValueError('Wrong project, malformed token, or privileged key rejected.') from None
    elif not key.startswith('sb_publishable_') or key == 'sb_publishable_':
        raise ValueError('Only a public client key is allowed.')


parser = argparse.ArgumentParser()
parser.add_argument('--from-cli', action='store_true')
parser.add_argument('--http-check', action='store_true')
parser.add_argument('--check', type=Path, metavar='PLIST', help='Validate a local app configuration without writing files or contacting the server.')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
if args.check:
    if args.from_cli or args.http_check:
        parser.error('--check cannot be combined with --from-cli or --http-check')
    try:
        configuration = plistlib.loads(args.check.read_bytes())
        if not isinstance(configuration, dict):
            raise ValueError()
        validate_key(configuration.get('publishableKey'))
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException, ExpatError):
        raise SystemExit(
            'error: Supabase public client configuration is missing or invalid. '
            'From the repository root, run: python3 scripts/configure-ios-service.py --from-cli --http-check. '
            'In CI, set OI_SUPABASE_PUBLISHABLE_KEY and run python3 scripts/configure-ios-service.py before building.'
        ) from None
    print('Validated Supabase public client configuration.')
    raise SystemExit(0)

key = os.environ.get('OI_SUPABASE_PUBLISHABLE_KEY', '')
if args.from_cli:
    result = subprocess.run(['supabase', 'projects', 'api-keys', '--project-ref', 'kfzfzarslqdqmrazohej', '-o', 'json'], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('Supabase key lookup failed. Verify CLI identity and project access.')
    records = json.loads(result.stdout)
    if isinstance(records, dict):
        records = records.get('keys', [])
    key = next((r['api_key'] for r in records if r.get('name') == 'anon' and not r.get('disabled')), '')
try:
    validate_key(key)
except ValueError as error:
    raise SystemExit(str(error)) from None

paths = [root / 'apps' / 'ios' / app / 'Service.local.plist' for app in ['OiDonation', 'OiDonationClip']]
data = plistlib.dumps({'publishableKey': key})
# Validate both destinations before changing either application's configuration.
for path in paths:
    if path.exists() and path.read_bytes() != data:
        raise SystemExit(f'Existing local configuration differs: {path}')
for path in paths:
    path.write_bytes(data)
    path.chmod(0o600)
print('Configured 52gibu public client key in ignored local app resources.')
if args.http_check:
    subprocess.run(['python3', str(root / 'supabase/tests/http-smoke.py')], env={**os.environ, 'OI_SUPABASE_PUBLISHABLE_KEY': key}, check=True)

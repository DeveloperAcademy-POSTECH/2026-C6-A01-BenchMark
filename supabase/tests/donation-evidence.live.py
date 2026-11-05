#!/usr/bin/env python3
"""Explicit paid end-to-end evaluation; no secrets or uploaded originals are written.

Uses the existing Supabase CLI identity. Creates one isolated test account and
private evidence records, then removes those exact files and requests. Account
self-membership cleanup is completed through the connected database tool before
--cleanup-account removes the exact test identity; no deletion policy is weakened.
Supply --sample-image only for a user-authorized local image. Reports enum
outcomes only; never logs document text, credentials, or actual model findings.
"""
import argparse
import json
from pathlib import Path
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

PROJECT = 'kfzfzarslqdqmrazohej'
BASE = f'https://{PROJECT}.supabase.co'


def synthetic_pdf(lines):
    escape = lambda s: s.replace('\\', '\\\\').replace('(', '\\(').replace(')', '\\)')
    content = 'BT /F1 14 Tf 45 740 Td 26 TL ' + ' '.join(f'({escape(line)}) Tj T*' for line in lines) + ' ET'
    objects = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        f'<< /Length {len(content)} >>\nstream\n{content}\nendstream', '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    pdf = '%PDF-1.4\n'
    offsets = [0]
    for index, obj in enumerate(objects, 1):
        offsets.append(len(pdf)); pdf += f'{index} 0 obj\n{obj}\nendobj\n'
    start = len(pdf)
    pdf += f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'
    pdf += ''.join(f'{offset:010d} 00000 n \n' for offset in offsets[1:])
    return (pdf + f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n').encode('ascii')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sample-image', type=Path)
    parser.add_argument('--only-cases', choices=['all','remaining'], default='all')
    parser.add_argument('--defer-account-cleanup', action='store_true')
    parser.add_argument('--cleanup-account', action='store_true')
    args = parser.parse_args()
    if not args.defer_account_cleanup and not args.cleanup_account:
        parser.error('Evaluation requires --defer-account-cleanup and connected DB cleanup of the isolated self-membership, followed by --cleanup-account')
    # Keys are captured in process memory only. Never put them in argv/env/files.
    raw = subprocess.run(['supabase', 'projects', 'api-keys', '--project-ref', PROJECT, '--output', 'json'],
        capture_output=True, text=True, check=True, timeout=30)
    keys = {item['name']: item['api_key'] for item in json.loads(raw.stdout)}
    raw = None
    service, public = keys['service_role'], keys['anon']
    keys = None
    owner = None
    paths, records = [], []
    passed, total = 0, 0
    failures = []
    window_start, attempts = None, 0
    registry = Path('/tmp/benchmark-tuning-live-registry.json')

    def call(path, method='GET', value=None, token=None, data=None, mime='application/json', admin=False):
        credential = service if admin else public
        headers = {'apikey': credential, 'Authorization': 'Bearer ' + (service if admin else token or public), 'Content-Type': mime}
        body = data if data is not None else json.dumps(value).encode() if value is not None else None
        request = urllib.request.Request(BASE + path, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=80) as response:
                payload = response.read(256 * 1024)
                return response.status, json.loads(payload) if payload else None
        except urllib.error.HTTPError as error:
            # Keep raw server error bodies out of logs and exception messages.
            try: payload = json.loads(error.read(4096))
            except (ValueError, UnicodeDecodeError): payload = {}
            return error.code, {'error': payload.get('error', payload.get('code', 'http_error'))}

    def require(status, payload, label):
        if status not in (200, 201, 204):
            raise RuntimeError(f'{label}: HTTP {status}, code={payload.get("error", "unknown") if isinstance(payload, dict) else "unknown"}')
        return payload

    def evidence(data, mime, token):
        identity = str(uuid.uuid4())
        records.append(identity)
        registry.write_text(json.dumps({'owner': owner, 'evidence': records, 'objects': paths, 'state': 'active'}))
        status, result = call('/rest/v1/rpc/oi_mutate', 'POST', {'p_action': 'start_evidence', 'p_payload': {'id': identity}}, token=token)
        require(status, result, 'start_evidence')
        path = f'{owner}/{identity}/{uuid.uuid4()}.{"jpg" if mime=="image/jpeg" else "pdf"}'
        paths.append(path)
        status, result = call('/storage/v1/object/oi-evidence/' + path, 'POST', token=token, data=data, mime=mime)
        require(status, result, 'upload')
        status, result = call('/rest/v1/rpc/oi_mutate', 'POST', {'p_action': 'submit_evidence', 'p_payload': {'id': identity, 'object_path': path}}, token=token)
        require(status, result, 'submit_evidence')
        registry.write_text(json.dumps({'owner': owner, 'evidence': records, 'objects': paths, 'state': 'active'}))
        return identity

    def evaluate(label, identity, expected, token):
        nonlocal attempts, window_start, passed, total
        if window_start is None: window_start = time.monotonic()
        elapsed = time.monotonic() - window_start
        if attempts >= 5 and elapsed < 66:
            delay = 66 - elapsed
            print(json.dumps({'rate_window_wait_seconds': round(delay)}), flush=True)
            while delay > 0:
                pause = min(delay, 20)
                time.sleep(pause); delay -= pause
            attempts = 0; window_start = time.monotonic()
        elif elapsed >= 66:
            attempts = 0; window_start = time.monotonic()
        attempts += 1; total += 1
        status, result = call('/functions/v1/analyze-donation-evidence', 'POST', {'evidence_id': identity}, token=token)
        result = require(status, result, label)
        outcome = result.get('summary', {}).get('outcome')
        correct = outcome in expected and result.get('writing_permission_granted') is False and result.get('human_review_required') is True
        print(json.dumps({'case': label, 'outcome': outcome, 'passed': correct, 'actual_model_call': True}), flush=True)
        passed += int(correct)
        if not correct: failures.append(label)

    if args.cleanup_account:
        state = json.loads(registry.read_text())
        identity = str(uuid.UUID(state['owner']))
        assert state['state'] == 'awaiting_account_cleanup'
        status, user = call('/auth/v1/admin/users/' + identity, admin=True)
        user = require(status, user, 'cleanup_identity_check')
        assert user['email'].startswith('oi-evidence-eval-') and user['email'].endswith('@example.test')
        status, result = call('/auth/v1/admin/users/' + identity, 'DELETE', admin=True)
        require(status, result, 'cleanup_test_account')
        status, _ = call('/auth/v1/admin/users/' + identity, admin=True)
        assert status == 404
        state['state'] = 'removed'; state['cleanup_errors'] = []
        registry.write_text(json.dumps(state))
        print(json.dumps({'account_cleanup':'passed', 'remaining_task_account':False}), flush=True)
        return

    if registry.exists() and json.loads(registry.read_text()).get('state') != 'removed':
        raise RuntimeError('The prior task account must be cleaned before another evaluation')
    try:
        password = secrets.token_urlsafe(32)
        email = f'oi-evidence-eval-{uuid.uuid4().hex}@example.test'
        status, user = call('/auth/v1/admin/users', 'POST', {'email': email, 'password': password, 'email_confirm': True,
            'user_metadata': {'nickname': 'Evidence evaluation'}}, admin=True)
        user = require(status, user, 'create_test_account')
        owner = user['id']
        registry.write_text(json.dumps({'owner': owner, 'evidence': [], 'objects': [], 'state': 'active'}))
        status, login = call('/auth/v1/token?grant_type=password', 'POST', {'email': email, 'password': password})
        login = require(status, login, 'sign_in')
        token = login['access_token']; password = None; login = None
        if args.only_cases == 'all':
            if args.sample_image:
                image = args.sample_image.read_bytes()
                sample = evidence(image, 'image/jpeg', token)
                evaluate('user_authorized_sms', sample, {'sufficient_evidence'}, token)
                evaluate('same_request_retry', sample, {'sufficient_evidence'}, token)
            pledge = synthetic_pdf(['SMS thread', 'Sender: +82 54-279-2417', 'POSTECH University Development Team',
                'We have received your donation pledge application.', 'Please pay your pledged donation using the instructions.', 'Contact: 054-279-2417'])
            evaluate('pledge_only', evidence(pledge, 'application/pdf', token), {'needs_more_evidence'}, token)
            transaction = 'TX-EVAL-' + uuid.uuid4().hex[:16].upper()
            paid_lines = ['SMS thread', 'Sender: +82 54-279-2417', 'POSTECH University Development Team',
                'We confirm that your donation has been received successfully.', 'Thank you for your donation.',
                f'Payment transaction reference: {transaction}', 'Contact: 054-279-2417']
            paid = synthetic_pdf(paid_lines)
            paid_id = evidence(paid, 'application/pdf', token)
            evaluate('paid_sms', paid_id, {'sufficient_evidence'}, token)
            evaluate('exact_replay', evidence(paid, 'application/pdf', token), {'duplicate_evidence'}, token)
            replay = synthetic_pdf(paid_lines + ['Please keep this payment confirmation.'])
            evaluate('transaction_reference_replay', evidence(replay, 'application/pdf', token), {'duplicate_evidence'}, token)
            spoof = synthetic_pdf(['SMS thread', 'Sender: 010-1234-5678', 'POSTECH University Development Team',
                'We confirm receipt of your donation.', 'Contact in message body only: 054-279-2417'])
            evaluate('body_only_official_phone', evidence(spoof, 'application/pdf', token), {'manual_review'}, token)
        cancelled = synthetic_pdf(['SMS thread', 'Sender: +82 54-279-2417', 'POSTECH University Development Team',
            'Your earlier donation was received.', 'Later update: the payment has been fully cancelled and refunded.'])
        evaluate('later_refund', evidence(cancelled, 'application/pdf', token), {'needs_more_evidence'}, token)
        inconsistent = synthetic_pdf(['BANK TRANSFER RECEIPT', 'Beneficiary: POSTECH University Development Fund',
            'Transfer status: completed', 'Amount: KRW 10,000', 'Amount in words: one hundred Korean won',
            'Total debited: KRW 100', 'Transaction reference: TX-EVAL-' + uuid.uuid4().hex[:16].upper()])
        evaluate('controlled_document_inconsistency', evidence(inconsistent, 'application/pdf', token), {'suspected_manipulation'}, token)
        status, grants = call(f'/rest/v1/oi_writing_grants?select=id&user_id=eq.{owner}', token=token)
        require(status, grants, 'grants_check')
        assert grants == [], 'The evaluation must not grant writing permission'
        print(json.dumps({'live_cases': total, 'passed': passed, 'failed': len(failures), 'writing_grants': 0}), flush=True)
    except Exception as error:
        print(json.dumps({'primary_failure': str(error), 'type': type(error).__name__}), flush=True)
        raise
    finally:
        cleanup_errors = []
        if owner:
            if paths:
                status, _ = call('/storage/v1/object/oi-evidence', 'DELETE', {'prefixes': paths}, admin=True)
                if status not in (200, 204): cleanup_errors.append('private_objects')
            if records:
                status, _ = call('/rest/v1/oi_evidence_requests?id=in.(' + ','.join(records) + ')&user_id=eq.' + owner, 'DELETE', admin=True)
                if status not in (200, 204): cleanup_errors.append('evidence_rows')
            # ON DELETE RESTRICT membership is cleaned by the connected DB tool
            # after verifying the exact test identity is otherwise empty. The
            # explicit --cleanup-account phase then uses the supported Auth API.
            registry.write_text(json.dumps({'owner': owner, 'evidence': records, 'objects': paths,
                'state': 'cleanup_failed' if cleanup_errors else 'awaiting_account_cleanup', 'cleanup_errors': cleanup_errors}))
            print(json.dumps({'document_cleanup': 'failed' if cleanup_errors else 'passed', 'account_cleanup': 'awaiting_connected_db_step', 'test_accounts': 1,
                'private_documents': len(paths), 'errors': cleanup_errors}), flush=True)
        if cleanup_errors: raise RuntimeError('Evaluation cleanup requires inspection of the task registry')
    if failures: raise RuntimeError('Live cases did not match policy: ' + ', '.join(failures))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        # Exception strings are constructed from labels/status codes only.
        print(json.dumps({'evaluation': 'failed', 'type': type(error).__name__, 'reason': str(error)}), file=sys.stderr)
        sys.exit(1)

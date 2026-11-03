import assert from 'node:assert/strict';
import test from 'node:test';
import { createHandler } from '../functions/account-merge/handler.ts';

const targetID = 'a1000000-0000-4000-8000-000000000001';
const sourceID = 'a1000000-0000-4000-8000-000000000002';
const targetSession = 'b1000000-0000-4000-8000-000000000001';
const sourceSession = 'b1000000-0000-4000-8000-000000000002';
const operationID = 'c1000000-0000-4000-8000-000000000001';
const challengeID = 'd1000000-0000-4000-8000-000000000001';
const now = 1800000000;
const base = 'https://project.supabase.co';
const configuration = { supabaseUrl: base, publicKey: 'public-test-key', serviceKey: 'private-service-test-key' };
function token(sub, sessionID, updates = {}) {
  const value = { sub, session_id: sessionID, iss: `${base}/auth/v1`, aud: 'authenticated', role: 'authenticated', exp: now + 3600,
    iat: now, amr: [{ method: 'oauth', timestamp: now - 10 }], ...updates };
  return `header.${Buffer.from(JSON.stringify(value)).toString('base64url')}.verified-by-auth-server`;
}
const targetToken = token(targetID, targetSession);
const sourceToken = token(sourceID, sourceSession);
function context(options = {}) {
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push({ url, init });
    if (options.networkFailure) throw new Error(`Never expose ${configuration.serviceKey}`);
    if (url.endsWith('/auth/v1/user')) {
      const target = init.headers.Authorization === `Bearer ${options.targetToken ?? targetToken}`;
      if (options.invalidUser) return Response.json({ error: 'invalid token' }, { status: 401 });
      return Response.json({ id: target ? targetID : options.sameAccount ? targetID : sourceID,
        identities: [{ provider: target ? 'google' : options.sameProvider ? 'google' : 'apple' }] });
    }
    assert.equal(url, `${base}/rest/v1/rpc/oi_merge_accounts`);
    assert.equal(init.headers.Authorization, `Bearer ${configuration.serviceKey}`);
    assert.equal(init.redirect, 'error');
    const args = JSON.parse(init.body);
    assert.equal(args.p_target_user_id, targetID); assert.equal(args.p_source_user_id, sourceID);
    assert.equal(args.p_target_session_id, targetSession); assert.equal(args.p_source_session_id, sourceSession);
    assert.ok(!init.body.includes(targetToken)); assert.ok(!init.body.includes(sourceToken));
    if (options.rpcRaw) return new Response('private upstream HTML or malformed response', { status: 502 });
    if (options.invalidReceipt) return Response.json({ account_id: 'not-a-uuid', already_merged: false });
    if (options.rpcError) return Response.json(options.rpcError, { status: options.rpcStatus ?? 409 });
    return Response.json(args.p_action === 'preview' ? { challenge_id: challengeID, target_account_id: targetID,
      source_account_id: sourceID, source_is_new: options.sourceIsNew ?? false, expires_at: '2027-01-15T08:05:00Z', counts: { stories: 2, collections: 1, favorites: 1, evidence: 2, grants: 2 } }
      : { account_id: targetID, already_merged: options.alreadyMerged ?? false });
  };
  return { calls, handler: createHandler(configuration, fetcher, () => now * 1000) };
}
function request(body = {}, target = targetToken) {
  return new Request('https://edge.example/account-merge', { method: 'POST', headers: { Authorization: `Bearer ${target}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'preview', operation_id: operationID, source_access_token: sourceToken, ...body }) });
}
async function expectFailure(options, body, status, code, suppliedToken) {
  const { handler, calls } = context(options);
  const response = await handler(request(body, suppliedToken));
  assert.equal(response.status, status);
  assert.equal((await response.json()).error, code);
  assert.equal(calls.filter(({ url }) => url.includes('/rpc/')).length, options.rpcError ? 1 : 0);
}

test('preview verifies both OAuth users and binds server-derived identities to the private RPC', async () => {
  const { handler, calls } = context(); const response = await handler(request());
  assert.equal(response.status, 200); assert.equal((await response.json()).challenge_id, challengeID);
  assert.equal(calls.length, 3); assert.equal(response.headers.get('Cache-Control'), 'no-store');
});
test('confirm requires explicit consent and challenge', async () => {
  await expectFailure({}, { action: 'confirm', challenge_id: challengeID }, 400, 'merge_consent_required');
  await expectFailure({}, { action: 'confirm', consent: true }, 400, 'merge_consent_required');
});
test('new-method and existing-account review both reuse the same source authentication proof', async () => {
  for (const sourceIsNew of [true, false]) {
    const { handler, calls } = context({ sourceIsNew });
    const preview = await handler(request());
    assert.equal((await preview.json()).source_is_new, sourceIsNew);
    const confirmed = await handler(request({ action: 'confirm', challenge_id: challengeID, consent: true }));
    assert.equal(confirmed.status, 200);
    assert.equal(calls.filter(({ url, init }) => url.endsWith('/auth/v1/user') && init.headers.Authorization === `Bearer ${sourceToken}`).length, 2);
    assert.equal(calls.filter(({ url }) => url.includes('/rpc/')).length, 2);
  }
});
test('invalid, expired, wrong-project and privileged proofs cannot invoke the merge RPC', async () => {
  await expectFailure({ invalidUser: true }, {}, 401, 'authentication_failed');
  for (const updates of [{ exp: now - 1 }, { role: 'service_role' }, { iss: 'https://another-project/auth/v1' }, { aud: 'another-audience' }]) {
    const value = token(targetID, targetSession, updates);
    await expectFailure({ targetToken: value }, {}, 401, 'authentication_failed', value);
  }
});
test('refreshing iat does not turn an old OAuth authentication into a recent proof', async () => {
  const value = token(targetID, targetSession, { iat: now, amr: [{ method: 'oauth', timestamp: now - 601 }] });
  await expectFailure({ targetToken: value }, {}, 401, 'recent_login_required', value);
});
test('both Google and Apple and two distinct users are required', async () => {
  await expectFailure({ sameProvider: true }, {}, 403, 'both_providers_required');
  const source = token(targetID, sourceSession);
  await expectFailure({ sameAccount: true }, { source_access_token: source }, 409, 'accounts_already_unified');
});
test('operator, expired challenge, replay conflict and RPC authorization failures remain explicit', async () => {
  for (const [message, code, status] of [['operator_accounts_cannot_merge', '42501', 403], ['merge_challenge_expired', '40001', 409],
    ['merge_operation_conflict', '40001', 409], ['merge_rate_limited', '53300', 429]]) {
    await expectFailure({ rpcError: { message, code } }, { action: 'confirm', challenge_id: challengeID, consent: true }, status, message);
  }
  await expectFailure({ rpcError: { message: 'permission denied for function', code: '42501' } }, {}, 403, 'merge_unavailable');
});
test('repeating a confirmed operation returns its idempotent receipt', async () => {
  const { handler } = context({ alreadyMerged: true });
  const response = await handler(request({ action: 'confirm', consent: true, challenge_id: challengeID }));
  assert.equal(response.status, 200); assert.deepEqual(await response.json(), { account_id: targetID, already_merged: true });
});
test('untrusted input, oversized body and failures do not reveal credentials', async () => {
  await expectFailure({}, { target_user_id: sourceID }, 400, 'invalid_merge_request');
  const { handler } = context();
  const oversized = await handler(request({ padding: 'x'.repeat(45000) })); assert.equal(oversized.status, 413);
  const failing = context({ networkFailure: true }); const response = await failing.handler(request());
  assert.equal(response.status, 503); const text = await response.text();
  assert.ok(!text.includes(targetToken)); assert.ok(!text.includes(sourceToken)); assert.ok(!text.includes(configuration.serviceKey));
});

test('a silent request stream is cancelled when the caller aborts', async () => {
  let cancelled = false;
  const body = new ReadableStream({ cancel() { cancelled = true; } });
  const controller = new AbortController();
  const { handler, calls } = context();
  const pending = handler(new Request('https://edge.example/account-merge', { method: 'POST', duplex: 'half', body,
    signal: controller.signal, headers: { Authorization: `Bearer ${targetToken}`, 'Content-Type': 'application/json' } }));
  controller.abort();
  const response = await Promise.race([pending, new Promise((_, reject) => { const timer = setTimeout(() => reject(new Error('Reader did not cancel')), 1000); timer.unref(); })]);
  assert.equal(response.status, 504); assert.equal(cancelled, true); assert.equal(calls.length, 0);
});
test('malformed upstream errors or receipts are unavailable failures without exposing details', async () => {
  for (const options of [{ rpcRaw: true }, { invalidReceipt: true }]) {
    const { handler } = context(options);
    const response = await handler(request({ action: 'confirm', challenge_id: challengeID, consent: true }));
    assert.equal(response.status, 503); assert.deepEqual(await response.json(), { error: 'merge_unavailable' });
  }
});

import test from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "../functions/delete-account/handler.ts";
import { createHandler as createAppleTokenHandler } from "../functions/apple-sign-in-token/handler.ts";
import { decryptAppleToken, encryptAppleToken } from "../functions/_shared/apple-credentials.ts";

const base = "https://fixture.supabase.co";
const owner = "d1690000-0000-4000-8000-000000000001";
const linked = "d1690000-0000-4000-8000-000000000002";
const session = "d1690000-0000-4000-8000-000000000011";
const path = linked + "/draft/image.png";
const now = 1793890000;
const key = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const apple = { clientId: "com.Spero.OiDonation", teamId: "TESTTEAMID", keyId: "TESTKEY123",
  privateKey: Buffer.from(await crypto.subtle.exportKey("pkcs8", key.privateKey)).toString("base64"),
  encryptionKey: Buffer.alloc(32, 7).toString("base64") };
const subject = "synthetic-apple-account";
const credential = { user_id: linked, subject, encrypted_token: null };

function appleExchange(subjectToReturn) {
  const idToken = { iss: "https://appleid.apple.com", aud: apple.clientId, exp: Date.now() / 1000 + 60, sub: subjectToReturn };
  return Response.json({ id_token: `header.${Buffer.from(JSON.stringify(idToken)).toString("base64url")}.signature`,
    refresh_token: "fresh-apple-refresh-token" });
}

function token(id, time = now) {
  return "header." + Buffer.from(JSON.stringify({ sub: id, session_id: session, exp: now + 1000,
    iss: base + "/auth/v1", role: "authenticated", amr: [{ method: "oauth", timestamp: time }] })).toString("base64url") + ".signature";
}

function fixture({ failStorage = false, forbidden = false, appleIdentities, exchangeSubject = subject,
  revokeStatus = 200, proofUser = linked } = {}) {
  const calls = [];
  let file = true;
  const handler = createHandler({ url: base, publicKey: "fake-public", serviceKey: "fake-service",
    apple: appleIdentities ? apple : undefined }, async (url, options) => {
    if (url.startsWith("https://appleid.apple.com/")) {
      const route = new URL(url).pathname;
      const body = Object.fromEntries(options.body);
      calls.push({ route, body });
      assert.equal(body.client_id, apple.clientId);
      assert.equal(options.redirect, "error");
      const [header, claims, signature] = body.client_secret.split(".");
      assert.equal(JSON.parse(Buffer.from(header, "base64url")).alg, "ES256");
      assert.equal(JSON.parse(Buffer.from(claims, "base64url")).sub, apple.clientId);
      assert.equal(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key.publicKey,
        Buffer.from(signature, "base64url"), Buffer.from(`${header}.${claims}`)), true);
      if (route === "/auth/token") return appleExchange(exchangeSubject);
      assert.equal(route, "/auth/revoke");
      return new Response(null, { status: revokeStatus });
    }
    const route = url.slice(base.length);
    const body = options.body && JSON.parse(options.body);
    calls.push({ route, body });
    if (route === "/auth/v1/user") {
      const claims = JSON.parse(Buffer.from(options.headers.Authorization.split(".")[1], "base64url"));
      return Response.json({ id: claims.sub });
    }
    assert.equal(options.headers.Authorization, "Bearer fake-service");
    if (route === "/rest/v1/rpc/oi_apple_revocation_credentials") {
      assert.deepEqual(body, { p_account: owner });
      return Response.json(appleIdentities);
    }
    if (route === "/storage/v1/object/oi-story-media") {
      assert.equal(options.method, "DELETE");
      assert.deepEqual(body, { prefixes: [path] });
      if (failStorage) return Response.json({}, { status: 500 });
      file = false;
      return Response.json([]);
    }
    assert.equal(route, "/rest/v1/rpc/oi_delete_account");
    assert.equal(body.p_account, owner);
    assert.equal(body.p_user, owner);
    assert.equal(body.p_proof_user, proofUser);
    if (forbidden) return Response.json({}, { status: 403 });
    if (body.p_action === "prepare") return Response.json({ files: file ? [{ bucket: "oi-story-media", name: path }] : [] });
    assert.equal(body.p_action, "finish");
    assert.equal(file, false);
    return Response.json({ deleted: true, apple_revocation_required: true, deleted_member_ids: [owner, linked] });
  }, () => now * 1000);
  const request = (proof = token(proofUser), consent = true, appleCode) => handler(new Request(base, { method: "POST",
    headers: { Authorization: "Bearer " + token(owner), "Content-Type": "application/json" },
    body: JSON.stringify({ account_id: owner, proof, consent, apple_code: appleCode }) }));
  return { calls, request };
}
test("deletes verified linked-account objects before finalization", async () => {
  const { request, calls } = fixture();
  const response = await request();
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).deleted_member_ids, [owner, linked]);
  assert.deepEqual(calls.slice(2).map(x => x.body.p_action ?? "storage"), ["prepare", "storage", "prepare", "finish"]);
});
test("failed storage cleanup never deletes Auth users", async () => {
  const { request, calls } = fixture({ failStorage: true });
  const response = await request();
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "deletion_incomplete");
  assert.ok(!calls.some(x => x.body?.p_action === "finish"));
});
test("blocks foreign proof without touching storage", async () => {
  const { request, calls } = fixture({ forbidden: true });
  assert.equal((await request()).status, 403);
  assert.ok(!calls.some(x => x.route.startsWith("/storage/")));
});
test("requires explicit consent and recent OAuth authentication", async () => {
  const { request, calls } = fixture();
  assert.equal((await request(token(linked), false)).status, 400);
  assert.equal(calls.length, 0);
  assert.equal((await request(token(linked, now - 601))).status, 401);
  assert.equal(calls.length, 2);
});

test("exchanges an existing Apple user's fresh code and revokes before final deletion", async () => {
  const { request, calls } = fixture({ appleIdentities: [credential] });
  const response = await request(undefined, true, "fresh-apple-code");
  assert.equal(response.status, 200);
  assert.equal((await response.json()).apple_revocation_required, false);
  const exchange = calls.find(call => call.route === "/auth/token");
  assert.equal(exchange.body.grant_type, "authorization_code");
  assert.equal(exchange.body.code, "fresh-apple-code");
  const revoke = calls.findIndex(call => call.route === "/auth/revoke");
  assert.equal(calls[revoke].body.token, "fresh-apple-refresh-token");
  assert.equal(calls[revoke].body.token_type_hint, "refresh_token");
  assert.equal(calls[revoke + 1].body.p_action, "finish");
});

test("Google reauthentication still revokes encrypted tokens of linked Apple identities", async () => {
  const stored = await encryptAppleToken(apple, subject, "stored-refresh-token");
  const second = await encryptAppleToken(apple, "second-subject", "second-stored-token");
  const { request, calls } = fixture({ proofUser: owner, appleIdentities: [
    { ...credential, encrypted_token: stored }, { user_id: owner, subject: "second-subject", encrypted_token: second },
  ] });
  const response = await request();
  assert.equal(response.status, 200);
  assert.equal((await response.json()).apple_revocation_required, false);
  assert.deepEqual(calls.filter(call => call.route === "/auth/revoke").map(call => call.body.token).sort(),
    ["second-stored-token", "stored-refresh-token"]);
});

test("a code for another Apple identity never causes revocation", async () => {
  const { request, calls } = fixture({ appleIdentities: [credential], exchangeSubject: "somebody-else" });
  const response = await request(undefined, true, "foreign-apple-code");
  assert.equal(response.status, 200);
  assert.equal((await response.json()).apple_revocation_required, true);
  assert.ok(!calls.some(call => call.route === "/auth/revoke"));
});

test("finishes deletion and reports manual disconnect when Apple revocation fails", async () => {
  const { request, calls } = fixture({ appleIdentities: [credential], revokeStatus: 503 });
  const response = await request(undefined, true, "fresh-apple-code");
  assert.equal(response.status, 200);
  assert.equal((await response.json()).apple_revocation_required, true);
  assert.equal(calls.at(-1).body.p_action, "finish");
});

test("stores only encrypted credentials bound to the signed-in Apple identity", async () => {
  let exchangeSubject = "somebody-else";
  const stored = [];
  const handler = createAppleTokenHandler({ url: base, publicKey: "fake-public", serviceKey: "fake-service", apple }, async (url, options) => {
    if (url.endsWith("/auth/v1/user")) return Response.json({ id: linked, identities: [{ provider: "apple", identity_data: { sub: subject } }] });
    if (url === "https://appleid.apple.com/auth/token") return appleExchange(exchangeSubject);
    assert.equal(url, `${base}/rest/v1/rpc/oi_store_apple_token`);
    assert.equal(options.headers.Authorization, "Bearer fake-service");
    stored.push(JSON.parse(options.body));
    return new Response(null, { status: 204 });
  });
  const submit = () => handler(new Request(base, { method: "POST", headers: { Authorization: "Bearer fake-auth",
    "Content-Type": "application/json" }, body: JSON.stringify({ code: "fresh-apple-code" }) }));
  assert.equal((await submit()).status, 403);
  assert.deepEqual(stored, []);
  exchangeSubject = subject;
  assert.equal((await submit()).status, 204);
  assert.equal(stored[0].p_user, linked);
  assert.equal(stored[0].p_subject, subject);
  assert.ok(!JSON.stringify(stored[0]).includes("fresh-apple-refresh-token"));
  assert.equal(await decryptAppleToken(apple, subject, stored[0].p_token), "fresh-apple-refresh-token");
  await assert.rejects(decryptAppleToken(apple, "different-subject", stored[0].p_token));
});

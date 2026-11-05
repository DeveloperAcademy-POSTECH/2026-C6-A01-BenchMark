import test from "node:test";
import assert from "node:assert/strict";
import { createHandler } from "../functions/delete-account/handler.ts";

const base = "https://fixture.supabase.co";
const owner = "d1690000-0000-4000-8000-000000000001";
const linked = "d1690000-0000-4000-8000-000000000002";
const session = "d1690000-0000-4000-8000-000000000011";
const path = linked + "/draft/image.png";
const now = 1793890000;
function token(id, time = now) {
  return "header." + Buffer.from(JSON.stringify({ sub: id, session_id: session, exp: now + 1000,
    iss: base + "/auth/v1", role: "authenticated", amr: [{ method: "oauth", timestamp: time }] })).toString("base64url") + ".signature";
}

function fixture({ failStorage = false, forbidden = false } = {}) {
  const calls = [];
  let file = true;
  const handler = createHandler({ url: base, publicKey: "fake-public", serviceKey: "fake-service" }, async (url, options) => {
    const route = url.slice(base.length);
    const body = options.body && JSON.parse(options.body);
    calls.push({ route, body });
    if (route === "/auth/v1/user") {
      const claims = JSON.parse(Buffer.from(options.headers.Authorization.split(".")[1], "base64url"));
      return Response.json({ id: claims.sub });
    }
    assert.equal(options.headers.Authorization, "Bearer fake-service");
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
    assert.equal(body.p_proof_user, linked);
    if (forbidden) return Response.json({}, { status: 403 });
    if (body.p_action === "prepare") return Response.json({ files: file ? [{ bucket: "oi-story-media", name: path }] : [] });
    assert.equal(body.p_action, "finish");
    assert.equal(file, false);
    return Response.json({ deleted: true, apple_revocation_required: true, deleted_member_ids: [owner, linked] });
  }, () => now * 1000);
  const request = (proof = token(linked), consent = true) => handler(new Request(base, { method: "POST",
    headers: { Authorization: "Bearer " + token(owner), "Content-Type": "application/json" },
    body: JSON.stringify({ account_id: owner, proof, consent }) }));
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

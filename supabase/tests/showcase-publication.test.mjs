import assert from "node:assert/strict";
import test from "node:test";
import { createShowcasePublicationHandler } from "../functions/publish-showcase-story/handler.ts";

const user = "a5080000-0000-4000-8000-000000000001";
const session = "a5080000-0000-4000-8000-000000000021";
const story = "a5080000-0000-4000-8000-000000000011";
const claims = { sub: user, role: "authenticated", session_id: session };
const submission = { id: story, revision: 1, card_snapshot_id: "a5080000-0000-4000-8000-000000000031" };
function setup({ authStatus = 200, rpcStatus = 200, anonymous = false, jwtClaims = claims } = {}) {
  const calls = [];
  const token = `fixture.${Buffer.from(JSON.stringify(jwtClaims)).toString("base64url")}.signature`;
  const handler = createShowcasePublicationHandler({
    supabaseUrl: "https://project.test", anonKey: "fixture-anon", serviceKey: "fixture-service",
  }, async (url, options) => {
    const path = new URL(url).pathname;
    calls.push(path);
    if (path === "/auth/v1/user") return Response.json({ id: user, is_anonymous: anonymous }, { status: authStatus });
    assert.equal(path, "/rest/v1/rpc/oi_publish_showcase_story");
    assert.equal(options.headers.Authorization, "Bearer fixture-service");
    assert.deepEqual(JSON.parse(options.body), { p_user: user, p_session: session, p_submission: submission });
    return Response.json({ id: story, revision: 2, status: "published" }, { status: rpcStatus });
  });
  return { calls, send: (body = { submission }, method = "POST") =>
    handler(new Request("https://edge.test", { method, headers: { Authorization: `Bearer ${token}` },
      body: method === "POST" ? JSON.stringify(body) : undefined })) };
}

test("direct installation publishes through Auth and guarded RPC without an app transaction", async () => {
  const { calls, send } = setup();
  const response = await send();
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, "published");
  assert.deepEqual(calls, ["/auth/v1/user", "/rest/v1/rpc/oi_publish_showcase_story"]);
});
for (const [name, options, status] of [
  ["invalid session", { authStatus: 401 }, 401],
  ["anonymous login", { anonymous: true }, 401],
  ["forged subject", { jwtClaims: { ...claims, sub: story } }, 401],
  ["missing persisted session claim", { jwtClaims: { sub: user, role: "authenticated" } }, 401],
]) test(`rejects ${name} before publication`, async () => {
  const { calls, send } = setup(options);
  assert.equal((await send()).status, status);
  assert.ok(!calls.includes("/rest/v1/rpc/oi_publish_showcase_story"));
});
for (const status of [402, 403, 409, 422, 503]) test(`preserves database denial ${status}`, async () => {
  assert.equal((await setup({ rpcStatus: status }).send()).status, status);
});
test("requires a bounded payload and valid campus revision", async () => {
  for (const body of [{}, { submission, padding: "x".repeat(33 * 1024) },
    { submission: { ...submission, revision: 0 } },
    { submission: { ...submission, scope: "education" } }]) {
    const { send, calls } = setup();
    assert.equal((await send(body)).status, 400);
    assert.deepEqual(calls, ["/auth/v1/user"]);
  }
  assert.equal((await setup().send({}, "GET")).status, 405);
});

test("direct publication insufficient balance reaches the existing coin recovery UI", async () => {
  const response = await setup({ rpcStatus: 402 }).send();
  assert.equal(response.status, 402);
  assert.deepEqual(await response.json(), { error: "pickle_coins_insufficient" });
});

test("existing TestFlight clients remain compatible without verifying their optional transaction", async () => {
  const { calls, send } = setup();
  assert.equal((await send({ submission, app_transaction: "old-client-transaction" })).status, 200);
  assert.deepEqual(calls, ["/auth/v1/user", "/rest/v1/rpc/oi_publish_showcase_story"]);
});

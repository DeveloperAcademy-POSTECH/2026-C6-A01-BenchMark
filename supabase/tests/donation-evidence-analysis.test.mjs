import test from "node:test";
import assert from "node:assert/strict";
import { createDonationHandler } from "../functions/analyze-donation-evidence/handler.ts";

const owner = "10000000-0000-4000-8000-000000000001";
const id = "20000000-0000-4000-8000-000000000001";
const path = `${owner}/${id}/attachment.png`;
const assessment = { verdict: "no_obvious_signs", readability: "readable", findings: [],
  limitations: ["진위와 실제 납입은 확인하지 않습니다."], manual_checks: ["운영자 검토가 필요합니다."] };
const config = { supabaseUrl: "https://supabase.example", supabaseKey: "test-public", openaiKey: "test-provider" };
const request = () => new Request("https://function.example", { method: "POST",
  headers: { Authorization: "Bearer test-session", "Content-Type": "application/json" }, body: JSON.stringify({ evidence_id: id }) });
function fixture(options = {}) {
  const calls = [];
  let reads = 0, authReads = 0;
  const fetcher = async (url, init) => {
    calls.push(String(url));
    assert.equal(init.redirect, "error");
    if (String(url).includes("api.openai.com")) {
      if (options.providerFailure) return new Response(null, { status: 503 });
      const payload = JSON.parse(init.body);
      assert.equal(payload.store, false);
      return Response.json({ status: "completed", output: [{ type: "message", role: "assistant",
        content: [{ type: "output_text", text: JSON.stringify(assessment) }] }] });
    }
    assert.equal(init.headers.Authorization, "Bearer test-session");
    if (url.endsWith("/auth/v1/user")) {
      authReads++;
      if (options.revoked && authReads > 1) return new Response(null, { status: 401 });
      return Response.json({ id: owner, is_anonymous: options.anonymous ?? false }, { status: options.authStatus ?? 200 });
    }
    if (url.includes("/rest/v1/oi_evidence_requests?")) {
      reads++;
      return Response.json([{ id, user_id: options.otherOwner ? "30000000-0000-4000-8000-000000000001" : owner,
        status: options.status ?? "pending", object_path: reads > 1 && options.changed ? `${owner}/${id}/replacement.png` : path,
        submitted_at: "2026-11-05T00:00:00Z" }]);
    }
    if (url.includes("/storage/v1/object/authenticated/oi-evidence/")) {
      return new Response(options.invalidFile ? new Uint8Array([1, 2]) : new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0]),
        { headers: { "Content-Type": "image/png" } });
    }
    assert.fail(`Unexpected service mutation or call: ${url}`);
  };
  return { calls, handler: createDonationHandler(config, fetcher) };
}

test("the submitter receives existing AI assessment without writing approval or requiring operator status", async () => {
  const { handler, calls } = fixture();
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const result = await response.json();
  assert.equal(result.evidence_id, id);
  assert.equal(result.review_type, "donation_evidence");
  assert.equal(result.human_review_required, true);
  assert.equal(result.authenticity_verified, false);
  assert.deepEqual(result.assessment, assessment);
  assert.equal(calls.filter(url => url.includes("api.openai.com")).length, 1);
  assert.equal(calls.some(url => url.includes("oi_capabilities") || url.includes("oi_mutate")), false);
});
for (const [name, options, status] of [
  ["another user's evidence", { otherOwner: true }, 404],
  ["anonymous accounts", { anonymous: true }, 401],
  ["expired sessions", { authStatus: 401 }, 401],
  ["already reviewed documents", { status: "approved" }, 409],
  ["invalid file contents", { invalidFile: true }, 415],
]) test(`rejects ${name} before provider billing`, async () => {
  const { handler, calls } = fixture(options);
  assert.equal((await handler(request())).status, status);
  assert.equal(calls.some(url => url.includes("api.openai.com")), false);
});
for (const [name, options, status] of [
  ["resubmission during analysis", { changed: true }, 409],
  ["revoked sessions during analysis", { revoked: true }, 401],
  ["provider errors", { providerFailure: true }, 502],
]) test(`does not return stale results after ${name}`, async () => {
  const { handler } = fixture(options);
  assert.equal((await handler(request())).status, status);
});
test("limits repeated analyses and rejects unconfigured and unauthenticated requests", async () => {
  const { handler } = fixture();
  for (let i = 0; i < 5; i++) assert.equal((await handler(request())).status, 200);
  assert.equal((await handler(request())).status, 429);
  assert.equal((await createDonationHandler({ ...config, openaiKey: "" })(request())).status, 503);
  assert.equal((await handler(new Request("https://function.example", { method: "POST" }))).status, 401);
});

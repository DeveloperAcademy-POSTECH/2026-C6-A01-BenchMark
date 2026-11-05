import test from "node:test";
import assert from "node:assert/strict";
import { createDonationHandler } from "../functions/analyze-donation-evidence/handler.ts";

const owner = "10000000-0000-4000-8000-000000000001";
const id = "20000000-0000-4000-8000-000000000001";
const path = `${owner}/${id}/attachment.png`;
const assessment = { verdict: "no_obvious_signs", readability: "readable", findings: [],
  limitations: ["진위와 실제 납입은 확인하지 않습니다."], manual_checks: ["운영자 검토가 필요합니다."] };
const config = { serviceKey: "test-service-role", supabaseUrl: "https://supabase.example", supabaseKey: "test-public", openaiKey: "test-provider" };
const request = () => new Request("https://function.example", { method: "POST",
  headers: { Authorization: "Bearer test-session", "Content-Type": "application/json" }, body: JSON.stringify({ evidence_id: id }) });
function fixture(options = {}) {
  const calls = [];
  const facts = { document_kind: "sms", institution: "postech", payment_state: "completed",
    completion_evidence: "incoming_acknowledgement", sender_phone: "+82 54-279-2417",
    sender_phone_location: "sender_header", recipient_matches_institution: true, chronology: "unclear",
    document_date: null, transaction_reference: null, reference_scope: "none", visual_review: assessment, ...options.facts };
  let reads = 0, authReads = 0, contextReads = 0;
  const fetcher = async (url, init) => {
    calls.push(String(url));
    assert.equal(init.redirect, "error");
    if (String(url).includes("api.openai.com")) {
      if (options.providerFailure) return new Response(null, { status: 503 });
      const payload = JSON.parse(init.body);
      assert.equal(payload.store, false);
      return Response.json({ status: "completed", output: [{ type: "message", role: "assistant",
        content: [{ type: "output_text", text: JSON.stringify(facts) }] }] });
    }
    if (url.endsWith("/rpc/oi_evidence_fingerprint_key")) {
      assert.equal(init.headers.Authorization, "Bearer test-service-role");
      if (options.vaultFailure) return new Response(null, {status:503});
      return Response.json(options.badKey ? "invalid" : "a".repeat(64));
    }
    if (url.endsWith("/rpc/oi_register_evidence_fingerprint")) {
      assert.equal(init.headers.Authorization, "Bearer test-service-role");
      assert.equal(init.headers.apikey, "test-service-role");
      const body = JSON.parse(init.body);
      assert.equal(body.p_user_id, owner);
      assert.equal(body.p_evidence_id, id);
      assert.match(body.p_sha256, /^[0-9a-f]{64}$/);
      if (facts.transaction_reference) {
        assert.match(body.p_semantic_digest, /^[0-9a-f]{64}$/);
        assert.equal(JSON.stringify(body).includes(facts.transaction_reference), false);
      } else assert.equal(body.p_semantic_digest, null);
      if (options.ledgerFailure) return new Response(null, { status: 503 });
      return Response.json(options.malformedLedger ? {} : {
        exact_duplicate: options.exactDuplicate ?? false,
        semantic_duplicate: options.semanticDuplicate ?? false, same_request: options.sameRequest ?? false,
      });
    }
    assert.equal(init.headers.Authorization, "Bearer test-session");
    if (url.endsWith("/auth/v1/user")) {
      authReads++;
      if (options.revoked && authReads > 1) return new Response(null, { status: 401 });
      return Response.json({ id: options.mergedLogin ? "40000000-0000-4000-8000-000000000001" : owner, is_anonymous: options.anonymous ?? false }, { status: options.authStatus ?? 200 });
    }
    if (url.endsWith("/rpc/oi_account_context")) {
      contextReads++;
      return Response.json({id: options.contextChanged && contextReads > 1 ? "50000000-0000-4000-8000-000000000001" : owner,
        auth_user_id: options.mergedLogin ? "40000000-0000-4000-8000-000000000001" : owner});
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
  assert.equal(result.summary.outcome, "sufficient_evidence");
  assert.equal(result.writing_permission_granted, false);
  assert.equal(result.summary.source_references.length, 3);
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

for (const [name, options, expected] of [
  ["exact reuse across requests", {exactDuplicate: true}, "duplicate_evidence"],
  ["transaction reference reuse", {semanticDuplicate: true}, "duplicate_evidence"],
  ["same request retry", {sameRequest: true}, "sufficient_evidence"],
]) test(`integrates private ledger: ${name}`, async () => {
  const {handler} = fixture(options);
  const response = await handler(request());
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.summary.outcome, expected);
  assert.equal(JSON.stringify(result).includes("test-service-role"), false);
  assert.equal("transaction_reference" in result, false);
});
for (const options of [{ledgerFailure: true}, {malformedLedger: true}]) test("does not claim sufficiency without a valid duplicate check", async () => {
  const {handler} = fixture(options);
  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "duplicate_check_unavailable");
});

test("merged provider login uses the canonical account without leaking foreign evidence", async () => {
  const {handler} = fixture({mergedLogin: true});
  assert.equal((await handler(request())).status, 200);
});
test("account merge during analysis withholds stale ownership results", async () => {
  const {handler} = fixture({contextChanged: true});
  const response = await handler(request());
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error, "account_changed");
});

test("unique references use a stable private Vault key and never leave plaintext in the ledger or response", async () => {
  const {handler, calls} = fixture({facts:{transaction_reference:"TX-EVAL-ABC12345", reference_scope:"transaction"}});
  const response = await handler(request());
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.summary.outcome, "sufficient_evidence");
  assert.equal(JSON.stringify(result).includes("TX-EVAL-ABC12345"), false);
  assert.equal(JSON.stringify(result).includes("a".repeat(64)), false);
  assert.equal(calls.filter(url => url.endsWith("oi_evidence_fingerprint_key")).length, 1);
});
for (const options of [{vaultFailure:true},{badKey:true}]) test("missing or malformed Vault key cannot produce semantic sufficiency", async () => {
  const {handler} = fixture({...options, facts:{transaction_reference:"TX-EVAL-ABC12345", reference_scope:"transaction"}});
  assert.equal((await handler(request())).status, 503);
});

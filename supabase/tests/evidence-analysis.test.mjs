import assert from "node:assert/strict";
import { test } from "node:test";
import { AnalysisError, analyzeDocument, documentType, MAX_FILE_BYTES, parseAssessment, readBounded } from "../functions/_shared/document-analysis.ts";
import { createHandler } from "../functions/analyze-evidence/handler.ts";

const actor = "10000000-0000-4000-8000-000000000001";
const evidenceId = "20000000-0000-4000-8000-000000000001";
const path = `${actor}/${evidenceId}/30000000-0000-4000-8000-000000000001.png`;
const png = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0]);
const assessment = () => ({ verdict: "no_obvious_signs", readability: "readable", findings: [],
  limitations: ["시각적 분석만으로 원본 진위와 실제 납입을 확인할 수 없습니다."], manual_checks: ["원본과 수납처 확인 자료를 운영자가 대조하세요."] });
const completed = (value = assessment()) => ({ status: "completed", output: [{ type: "message", role: "assistant",
  content: [{ type: "output_text", text: JSON.stringify(value) }] }] });
const config = { supabaseUrl: "https://supabase.example", supabaseKey: "test-public-key", openaiKey: "test-only-key" };
const request = (value = { evidence_id: evidenceId }, headers = {}) => new Request("https://function.example/analyze-evidence", {
  method: "POST", headers: { Authorization: "Bearer test-user-session", "Content-Type": "application/json", ...headers }, body: JSON.stringify(value),
});

function fixture(overrides = {}) {
  const calls = [];
  let reads = 0, capabilities = 0;
  const row = { id: evidenceId, user_id: actor, status: "pending", object_path: path, submitted_at: "2026-11-02T00:00:00Z" };
  const fetcher = async (url, init) => {
    calls.push({ url, init });
    assert.equal(init.redirect, "error");
    if (String(url).startsWith("https://api.openai.com/")) {
      assert.equal(init.headers.Authorization, "Bearer test-only-key");
      if (overrides.provider) return overrides.provider(url, init);
      return Response.json(completed());
    }
    assert.equal(init.headers.Authorization, "Bearer test-user-session");
    assert.equal(init.headers.apikey, "test-public-key");
    if (url.endsWith("/auth/v1/user")) return Response.json({ id: actor }, { status: overrides.authStatus ?? 200 });
    if (url.endsWith("/rpc/oi_capabilities")) {
      capabilities++;
      return Response.json({ operator: overrides.operator !== false && !(overrides.revoke && capabilities > 1) });
    }
    if (url.includes("/oi_evidence_requests?")) {
      reads++;
      return Response.json(overrides.missing ? [] : [{ ...row, ...overrides.row,
        ...(reads > 1 ? overrides.changed : {}) }]);
    }
    if (url.includes("/storage/v1/object/authenticated/oi-evidence/")) return new Response(overrides.bytes ?? png, {
      status: overrides.storageStatus ?? 200, headers: { "Content-Type": overrides.mime ?? "image/png" },
    });
    assert.fail(`Unexpected call: ${url}`);
  };
  return { calls, handler: createHandler(config, fetcher) };
}

test("images use high-detail input and strict structured output without storage or tools", async () => {
  let sent;
  const result = await analyzeDocument({ bytes: png, contentType: "image/png", apiKey: "test-key", signal: AbortSignal.timeout(1000),
    fetcher: async (url, init) => { assert.equal(url, "https://api.openai.com/v1/responses"); sent = JSON.parse(init.body); return Response.json(completed()); } });
  assert.equal(result.verdict, "no_obvious_signs");
  assert.equal(sent.store, false);
  assert.equal(sent.text.format.strict, true);
  assert.equal(sent.input[0].content[1].detail, "high");
  assert.match(sent.input[0].content[1].image_url, /^data:image\/png;base64,/);
  assert.equal(sent.tools, undefined);
  assert.match(sent.instructions, /untrusted evidence/);
});

test("PDFs are attached as base64 file inputs with a generic filename", async () => {
  await analyzeDocument({ bytes: new TextEncoder().encode("%PDF-1.4\nsynthetic fixture"), contentType: "application/pdf", apiKey: "test-key",
    signal: AbortSignal.timeout(1000), fetcher: async (_url, init) => {
      const file = JSON.parse(init.body).input[0].content[1];
      assert.equal(file.type, "input_file"); assert.equal(file.filename, "evidence.pdf");
      assert.match(file.file_data, /^data:application\/pdf;base64,/);
      return Response.json(completed());
    } });
});

for (const [name, value] of [
  ["suspicions without observations", { ...assessment(), verdict: "suspicious" }],
  ["unreadable material treated as clean", { ...assessment(), readability: "unreadable" }],
  ["limited material treated as clean", { ...assessment(), readability: "limited" }],
  ["unknown fields", { ...assessment(), approved: true }],
  ["coerced verdict", { ...assessment(), verdict: ["no_obvious_signs"] }],
  ["coerced readability", { ...assessment(), readability: ["readable"] }],
  ["coerced category", { ...assessment(), verdict: "suspicious", findings: [{ category: ["visual_edit"], location: "금액", observation: "글꼴 불일치" }] }],
  ["clean verdict with suspicious findings", { ...assessment(), findings: [{ category: "visual_edit", location: "금액", observation: "글꼴 불일치" }] }],
  ["empty limitations", { ...assessment(), limitations: [] }],
  ["invalid category", { ...assessment(), verdict: "suspicious", findings: [{ category: "fraud", location: "금액", observation: "글꼴 불일치" }] }],
  ["overlong output", { ...assessment(), manual_checks: ["x".repeat(501)] }],
]) test(`rejects ${name}`, () => assert.throws(() => parseAssessment(value), AnalysisError));

test("accepts observable suspicions and inconclusive results without treating them as approval", () => {
  assert.equal(parseAssessment({ ...assessment(), verdict: "suspicious", findings: [{ category: "visual_edit", location: "금액 필드 주변", observation: "주변 배경과 경계가 불연속입니다." }] }).verdict, "suspicious");
  assert.equal(parseAssessment({ ...assessment(), verdict: "inconclusive", readability: "unreadable" }).verdict, "inconclusive");
});

test("MIME and signatures must match; empty and oversized files are rejected", () => {
  assert.equal(documentType(new Uint8Array([255, 216, 255, 224]), "image/jpeg"), "image/jpeg");
  assert.throws(() => documentType(png, "image/jpeg"), { code: "unsupported_document" });
  assert.throws(() => documentType(png, "text/html"), { code: "unsupported_document" });
  assert.throws(() => documentType(new Uint8Array(), "image/png"), { code: "empty_document" });
  assert.throws(() => documentType(new Uint8Array(MAX_FILE_BYTES + 1), "image/png"), { code: "payload_too_large" });
});

test("stream limits apply without Content-Length and cancel the reader", async () => {
  let cancelled = false;
  const stream = new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array(11)); }, cancel() { cancelled = true; } });
  await assert.rejects(readBounded(new Response(stream), 10), { code: "payload_too_large" });
  assert.equal(cancelled, true);
});

test("a stalled response body is cancelled on timeout", async () => {
  const controller = new AbortController(); let cancelled = false;
  const reading = readBounded(new Response(new ReadableStream({ cancel() { cancelled = true; } })), 10, controller.signal);
  controller.abort();
  await assert.rejects(reading, { name: "AbortError" });
  assert.equal(cancelled, true);
});

for (const [name, provider, code] of [
  ["refusal", async () => Response.json({ status: "completed", output: [{ type: "message", role: "assistant", content: [{ type: "refusal", refusal: "Cannot analyze" }] }] }), "analysis_refused"],
  ["truncation", async () => Response.json({ status: "incomplete", output: [] }), "incomplete_analysis"],
  ["invalid JSON", async () => new Response("invalid"), "invalid_analysis_response"],
  ["missing output", async () => Response.json({ status: "completed", output: [] }), "invalid_analysis_response"],
  ["oversized provider response", async () => new Response("x".repeat(65537)), "invalid_analysis_response"],
  ["provider rate limit", async () => new Response("private provider details", { status: 429 }), "provider_rate_limited"],
  ["provider credential error", async () => new Response("private provider details", { status: 401 }), "analysis_unavailable"],
  ["network failure", async () => { throw new Error("private provider details"); }, "analysis_unavailable"],
]) test(`handles ${name} without exposing upstream details`, async () => {
  await assert.rejects(analyzeDocument({ bytes: png, contentType: "image/png", apiKey: "test-key", signal: AbortSignal.timeout(1000), fetcher: provider }), { code });
});

test("aborted upstream request is a failure, never a clean result", async () => {
  const controller = new AbortController(); controller.abort();
  await assert.rejects(analyzeDocument({ bytes: png, contentType: "image/png", apiKey: "test-key", signal: controller.signal,
    fetcher: async () => { throw new DOMException("aborted", "AbortError"); } }), { code: "analysis_timeout" });
});

test("operator analyzes only the referenced private pending evidence without mutating state", async () => {
  const { handler, calls } = fixture();
  const response = await handler(request()); const body = await response.json();
  assert.equal(response.status, 200); assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(body.evidence_id, evidenceId); assert.match(body.sha256, /^[a-f0-9]{64}$/);
  assert.equal(body.human_review_required, true); assert.equal(body.authenticity_verified, false);
  assert.equal(body.object_path, undefined);
  assert.equal(calls.filter(({ url }) => url.includes("api.openai.com")).length, 1);
  assert.ok(calls.every(({ url, init }) => !url.includes("oi_mutate") && (!init.method || init.method === "POST")));
});

test("merged evidence retains its original Storage prefix while canonical ownership changes", async () => {
  const { handler } = fixture({ row: { user_id: "10000000-0000-4000-8000-000000000002", storage_owner_id: actor } });
  assert.equal((await handler(request())).status, 200);
});

for (const [name, overrides, status, code] of [
  ["expired session", { authStatus: 401 }, 401, "authentication_failed"],
  ["non-operator", { operator: false }, 403, "operator_required"],
  ["missing evidence", { missing: true }, 404, "evidence_not_found"],
  ["unsubmitted evidence", { row: { status: "draft" } }, 409, "evidence_not_pending"],
  ["already reviewed evidence", { row: { status: "approved" } }, 409, "evidence_not_pending"],
  ["foreign path", { row: { object_path: `other/${evidenceId}/image.png` } }, 409, "invalid_evidence_reference"],
  ["traversal path", { row: { object_path: `${actor}/${evidenceId}/..` } }, 409, "invalid_evidence_reference"],
  ["missing private object", { storageStatus: 404 }, 503, "evidence_download_failed"],
  ["forged MIME", { mime: "application/pdf" }, 415, "unsupported_document"],
]) test(`blocks ${name} before contacting OpenAI`, async () => {
  const { handler, calls } = fixture(overrides); const response = await handler(request());
  assert.equal(response.status, status); assert.equal((await response.json()).error, code);
  assert.equal(calls.filter(({ url }) => url.includes("api.openai.com")).length, 0);
});

test("requires a user token, POST, and server-side API key", async () => {
  const { handler, calls } = fixture();
  assert.equal((await handler(new Request("https://function.example", { method: "POST" }))).status, 401);
  assert.equal((await handler(new Request("https://function.example"))).status, 405);
  assert.equal((await createHandler({ ...config, openaiKey: "" })(request())).status, 503);
  assert.equal(calls.length, 0);
});

test("does not accept URLs, arbitrary object paths, malformed IDs or extra context", async () => {
  for (const value of [{ evidence_id: "https://private.example" }, { evidence_id: evidenceId, object_path: path }, null, [], {}]) {
    const { handler, calls } = fixture(); assert.equal((await handler(request(value))).status, 400);
    assert.equal(calls.filter(({ url }) => url.includes("api.openai.com")).length, 0);
  }
  assert.equal((await fixture().handler(request({ evidence_id: evidenceId }, { "Content-Type": "text/plain" }))).status, 415);
});

for (const [name, overrides] of [
  ["replacement upload", { changed: { object_path: `${actor}/${evidenceId}/new.png` } }],
  ["resubmission timestamp", { changed: { submitted_at: "2026-11-02T01:00:00Z" } }],
  ["concurrent review", { changed: { status: "rejected" } }],
  ["operator revocation", { revoke: true }],
]) test(`discards result after ${name}`, async () => {
  const response = await fixture(overrides).handler(request());
  assert.equal(response.status, overrides.revoke ? 403 : 409);
  assert.equal((await response.json()).assessment, undefined);
});

test("duplicate in-flight analysis is blocked and failure releases its slot", async () => {
  let release, started;
  const ready = new Promise((resolve) => { started = resolve; });
  const pending = new Promise((resolve) => { release = resolve; });
  const { handler } = fixture({ provider: async () => { started(); await pending; return new Response("failed", { status: 500 }); } });
  const first = handler(request()); await ready;
  assert.equal((await handler(request())).status, 429);
  release(); assert.equal((await first).status, 502);
  assert.equal((await handler(request())).status, 502);
});

test("per-isolate actor rate limit bounds repeated paid calls", async () => {
  const { handler, calls } = fixture();
  for (let i = 0; i < 5; i++) assert.equal((await handler(request())).status, 200);
  const limited = await handler(request()); assert.equal(limited.status, 429);
  assert.equal((await limited.json()).error, "analysis_rate_limited");
  assert.equal(calls.filter(({ url }) => url.includes("api.openai.com")).length, 5);
});

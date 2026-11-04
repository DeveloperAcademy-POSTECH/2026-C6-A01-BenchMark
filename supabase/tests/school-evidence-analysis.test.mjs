import assert from "node:assert/strict";
import test from "node:test";
import { createSchoolHandler } from "../functions/analyze-school-evidence/handler.ts";

const pdf = "%PDF-1.4\nSynthetic school affiliation fixture";
const assessment = {
  verdict: "inconclusive",
  readability: "limited",
  findings: [],
  limitations: ["소속 항목을 판독할 수 없습니다."],
  manual_checks: ["발급처와 소속 유효 기간을 확인하세요."],
};
const request = ({ token = "user-jwt", body = pdf, type = "application/pdf", length } = {}) =>
  new Request("https://edge.example/analyze-school-evidence", {
    method: "POST",
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      "content-type": type,
      ...(length === undefined ? {} : { "content-length": String(length) }),
    },
    body,
  });

function fixture({ enabled = true, validSession = () => true, anonymous = false, output = assessment } = {}) {
  const calls = [];
  let checks = 0;
  const handler = createSchoolHandler({
    enabled, supabaseUrl: "https://db.example", supabaseKey: "publishable", openaiKey: "test-key",
  }, async (url, init) => {
    const target = String(url);
    calls.push(target);
    if (target.startsWith("https://db.example/")) {
      assert.equal(init.headers.Authorization, "Bearer user-jwt");
      assert.equal(init.headers.apikey, "publishable");
    }
    if (target === "https://db.example/auth/v1/user") {
      return !validSession(++checks) ? new Response(null, { status: 401 })
        : Response.json({ id: "12345678-1234-1234-1234-123456789abc", is_anonymous: anonymous });
    }
    assert.equal(target, "https://api.openai.com/v1/responses");
    const payload = JSON.parse(init.body);
    assert.match(payload.instructions, /school affiliation document/);
    assert.match(payload.instructions, /untrusted evidence/);
    assert.equal(payload.store, false);
    assert.equal(payload.tools, undefined);
    assert.equal(payload.text.format.name, "school_affiliation_review");
    assert.equal(payload.text.format.strict, true);
    const attachment = payload.input[0].content[1];
    assert.equal(attachment.filename, "evidence.pdf");
    assert.equal(attachment.file_data, `data:application/pdf;base64,${btoa(pdf)}`);
    return Response.json({
      status: "completed",
      output: [{ type: "message", role: "assistant", content: [{ type: "output_text", text: JSON.stringify(output) }] }],
    });
  });
  return { handler, calls };
}

test("ordinary users can review evidence with session checks before and after analysis", async () => {
  const { handler, calls } = fixture();
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const result = await response.json();
  assert.equal(result.review_type, "school_affiliation");
  assert.equal(result.human_review_required, true);
  assert.equal(result.affiliation_verified, false);
  assert.equal(result.authenticity_verified, false);
  assert.deepEqual(result.assessment, assessment);
  assert.deepEqual(calls.map((url) => new URL(url).pathname), [
    "/auth/v1/user", "/v1/responses", "/auth/v1/user",
  ]);
});

for (const [name, options, input, status, code] of [
  ["disabled function", { enabled: false }, {}, 503, "analysis_not_configured"],
  ["missing session", {}, { token: "" }, 401, "authentication_required"],
  ["invalid session", { validSession: () => false }, {}, 401, "authentication_failed"],
  ["anonymous session", { anonymous: true }, {}, 401, "authentication_failed"],
  ["client supplied URL", {}, { type: "application/json", body: '{"url":"https://example.com"}' }, 415, "unsupported_document"],
  ["invalid signature", {}, { body: "not a PDF" }, 415, "unsupported_document"],
  ["oversized document", {}, { length: 10 * 1024 * 1024 + 1 }, 413, "payload_too_large"],
]) {
  test(`blocks ${name} before calling OpenAI`, async () => {
    const { handler, calls } = fixture(options);
    const response = await handler(request(input));
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), { error: code });
    assert.equal(calls.some((url) => new URL(url).hostname === "api.openai.com"), false);
  });
}

test("invalidated session during analysis withholds the result", async () => {
  const { handler } = fixture({ validSession: (check) => check === 1 });
  const response = await handler(request());
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "authentication_failed" });
});

test("a provider-generated approval field is rejected", async () => {
  const { handler } = fixture({ output: { ...assessment, affiliation_verified: true } });
  const response = await handler(request());
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "invalid_analysis_response" });
});

test("rate limiting stops repeated requests before another provider call", async () => {
  const { handler, calls } = fixture();
  for (let i = 0; i < 5; i++) assert.equal((await handler(request())).status, 200);
  const response = await handler(request());
  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { error: "analysis_rate_limited" });
  assert.equal(calls.filter((url) => new URL(url).hostname === "api.openai.com").length, 5);
});

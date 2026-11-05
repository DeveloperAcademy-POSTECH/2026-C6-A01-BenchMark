import assert from "node:assert/strict";
import test from "node:test";
import { createSchoolHandler } from "../functions/analyze-school-evidence/handler.ts";

const pdf = "%PDF-1.4\nSynthetic school affiliation fixture";
const outputFixture = {
  document_kind: "student_card",
  readability: "readable",
  school_marking: "visible",
  affiliation_marking: "visible",
  reference_match: "none",
  visual_issues: [],
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

function fixture({ enabled = true, validSession = () => true, anonymous = false, output = outputFixture } = {}) {
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
  assert.equal(result.holder_verified, false);
  assert.equal(result.authenticity_verified, false);
  assert.equal(result.summary.outcome, "school_evidence_visible");
  assert.equal(result.assessment.verdict, "no_obvious_signs");
  assert.equal(result.assessment.readability, "readable");
  assert.equal(result.assessment.findings.length, 0);
  assert.match(result.summary.title, /학교 소속 근거/);
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

for (const { name, signals, outcome, verdict, nextStep } of [
  {
    name: "school certificate with visible affiliation",
    signals: { document_kind: "school_certificate" },
    outcome: "school_evidence_visible", verdict: "no_obvious_signs", nextStep: /재학증명서/,
  },
  {
    name: "third-party app profile with fully legible school and affiliation",
    signals: { document_kind: "third_party_profile" },
    outcome: "school_evidence_visible", verdict: "no_obvious_signs", nextStep: /공식 재학 확인/,
  },
  {
    name: "third-party app profile with missing affiliation",
    signals: { document_kind: "third_party_profile", affiliation_marking: "missing" },
    outcome: "school_document_needed", verdict: "inconclusive", nextStep: /계정의 소속 표기/,
  },
  {
    name: "third-party app profile with a concrete visual edit",
    signals: { document_kind: "third_party_profile", visual_issues: [{ kind: "typography_mismatch", location: "affiliation_marking" }] },
    outcome: "manual_review_needed", verdict: "suspicious", nextStep: /원본과 비교/,
  },
  {
    name: "payment side of a potentially dual-use card",
    signals: { document_kind: "payment_card", school_marking: "missing", affiliation_marking: "missing" },
    outcome: "school_document_needed", verdict: "inconclusive", nextStep: /학생증 표기가 있는 면/,
  },
  {
    name: "card with one missing affiliation marking",
    signals: { affiliation_marking: "missing" },
    outcome: "school_document_needed", verdict: "inconclusive", nextStep: /학생증 표기가 있는 면/,
  },
  {
    name: "student card with unreadable affiliation",
    signals: { readability: "limited", affiliation_marking: "unclear" },
    outcome: "retake_needed", verdict: "inconclusive", nextStep: /빛 반사/,
  },
  {
    name: "student card with conflicting school markings",
    signals: { visual_issues: [{ kind: "conflicting_markings", location: "school_marking" }] },
    outcome: "manual_review_needed", verdict: "suspicious", nextStep: /원본과 비교/,
  },
]) {
  test(`classifies ${name} with a specific Korean next step`, async () => {
    const { handler } = fixture({ output: { ...outputFixture, ...signals } });
    const response = await handler(request());
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.summary.outcome, outcome);
    assert.equal(result.assessment.verdict, verdict);
    assert.match(result.summary.next_step, nextStep);
    assert.match(result.summary.detail, /[가-힣]/);
    assert.equal(result.affiliation_verified, false);
    assert.equal(result.holder_verified, false);
    assert.equal(result.authenticity_verified, false);
  });
}

test("only a matching student card receives the trusted co-branded reference", async () => {
  const matching = { ...outputFixture, reference_match: "postech_woori_student_card" };
  const cardResponse = await fixture({ output: matching }).handler(request());
  const card = await cardResponse.json();
  assert.equal(card.summary.reference.url, "https://freshman.postech.ac.kr/freshman/ot/ot_document.do");
  assert.equal(card.authenticity_verified, false);
  const profileResponse = await fixture({ output: { ...matching, document_kind: "third_party_profile" } }).handler(request());
  const profile = await profileResponse.json();
  assert.equal(profile.summary.reference, undefined);
  const paymentResponse = await fixture({ output: { ...matching, document_kind: "payment_card" } }).handler(request());
  const payment = await paymentResponse.json();
  assert.equal(payment.summary.reference, undefined);
});

test("unrecognized model output cannot echo personal text", async () => {
  const { handler } = fixture({
    output: { ...outputFixture, visual_issues: [{ kind: "typography_mismatch", location: "Synthetic Person 0000000" }] },
  });
  const response = await handler(request());
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "invalid_analysis_response" });
});

test("invalidated session during analysis withholds the result", async () => {
  const { handler } = fixture({ validSession: (check) => check === 1 });
  const response = await handler(request());
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "authentication_failed" });
});

test("a provider-generated approval field is rejected", async () => {
  const { handler } = fixture({ output: { ...outputFixture, affiliation_verified: true } });
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

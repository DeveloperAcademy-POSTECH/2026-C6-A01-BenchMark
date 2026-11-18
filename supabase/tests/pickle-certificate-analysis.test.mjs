import assert from "node:assert/strict";
import test from "node:test";
import { createDonationHandler } from "../functions/analyze-donation-evidence/handler.ts";
import { certificateDecision, certificateDigests, parseCertificate } from "../functions/analyze-donation-evidence/certificate-assessment.ts";

const user = "a5060000-0000-4000-8000-000000000001";
const account = "a5060000-0000-4000-8000-000000000002";
const session = "a5060000-0000-4000-8000-000000000003";
const id = "a5060000-0000-4000-8000-000000000004";
const jwt = `fixture.${Buffer.from(JSON.stringify({ sub: user, role: "authenticated", session_id: session })).toString("base64url")}.signature`;
const pdf = "%PDF-1.7\nSynthetic certificate fixture";
const secret = "c".repeat(64);
const certificate = {
  document_kind: "donation_certificate", institution: "postech", issuer_name: "포항공과대학교 발전기금",
  issued_document: "issued", payment_state: "completed", readability: "readable", visual_consistency: "clear",
  transaction_count: "single", donor_name: "Synthetic Donor", donation_date: "2026-10-01",
  certificate_reference: "CERT-2026-000001", amount: 1000, amount_in_words: null, currency: "KRW",
};
const evidence = {
  id, user_id: account, storage_owner_id: user, status: "pending", object_path: `${user}/${id}/certificate.pdf`,
  submitted_at: "2026-11-18T00:00:00.000Z", coin_verification: true, coin_consent_version: 1, review_note: null,
};
const wallet = { account_id: account, balance: 40, unlimited: false, plant_cost: 30, outfit_cost: 3, owned_items: [] };

function setup(options = {}) {
  const calls = [];
  let authCount = 0;
  let contextCount = 0;
  let rowCount = 0;
  const row = { ...evidence, ...options.row };
  const facts = { ...certificate, ...options.facts };
  const handler = createDonationHandler({ supabaseUrl: "https://project.test", supabaseKey: "fixture-publishable",
    serviceKey: "fixture-service", openaiKey: "fixture-openai", ...options.config }, async (url, init) => {
    const target = new URL(url);
    const body = init.body === undefined ? undefined : JSON.parse(init.body);
    calls.push({ path: target.pathname, body });
    if (target.hostname === "api.openai.com") {
      assert.equal(init.headers.Authorization, "Bearer fixture-openai");
      assert.equal(body.store, false);
      assert.equal(body.tools, undefined);
      assert.match(body.instructions, /UNTRUSTED DATA/);
      assert.match(body.instructions, /NO MINIMUM donation amount/);
      assert.equal(body.text.format.name, "pickle_coin_certificate");
      assert.equal(body.text.format.strict, true);
      const attachment = body.input[0].content[1];
      assert.equal(attachment.type, options.mime === "image/png" ? "input_image" : "input_file");
      if (!options.mime) assert.equal(attachment.file_data, `data:application/pdf;base64,${btoa(pdf)}`);
      if (options.holdProvider) await options.holdProvider;
      if (options.abort) options.abort.abort();
      if (options.providerStatus) return Response.json({}, { status: options.providerStatus });
      const content = options.refusal ? [{ type: "refusal" }] : [{ type: "output_text", text: JSON.stringify(facts) }];
      return Response.json({ status: options.incomplete ? "incomplete" : "completed", output: [{ type: "message", role: "assistant", content }] });
    }
    if (target.pathname === "/auth/v1/user") {
      authCount += 1;
      if (options.authStatus || options.failReauth && authCount === 2) return Response.json({}, { status: options.authStatus ?? 401 });
      return Response.json({ id: user, is_anonymous: options.anonymous ?? false });
    }
    if (target.pathname === "/rest/v1/rpc/oi_account_context") {
      contextCount += 1;
      return Response.json({ id: options.mergeDuringAnalysis && contextCount === 2 ? user : account, auth_user_id: user });
    }
    if (target.pathname === "/rest/v1/oi_evidence_requests") {
      rowCount += 1;
      if (options.hidden) return Response.json([]);
      return Response.json([{ ...row, ...(rowCount === 2 ? options.changedRow : {}) }]);
    }
    if (target.pathname === "/rest/v1/rpc/oi_prepare_coin_evidence") {
      assert.equal(init.headers.Authorization, "Bearer fixture-service");
      assert.deepEqual(body, { p_user: user, p_session: session, p_request: id });
      return Response.json(row, { status: options.prepareStatus ?? 200 });
    }
    if (target.pathname.startsWith("/storage/v1/object/authenticated/oi-evidence/")) {
      assert.equal(init.headers.Authorization, `Bearer ${jwt}`);
      assert.equal(target.pathname, `/storage/v1/object/authenticated/oi-evidence/${row.object_path}`);
      const mime = options.mime ?? "application/pdf";
      const headers = { "content-type": mime, ...(options.length ? { "content-length": String(options.length) } : {}) };
      return new Response(options.bytes ?? pdf, { status: options.storageStatus ?? 200, headers });
    }
    if (target.pathname === "/rest/v1/rpc/oi_evidence_fingerprint_key") {
      assert.equal(init.headers.Authorization, "Bearer fixture-service");
      return Response.json(secret);
    }
    if (target.pathname === "/rest/v1/rpc/oi_pickle_wallet") return Response.json(wallet);
    assert.equal(target.pathname, "/rest/v1/rpc/oi_coin_evidence_review");
    assert.equal(init.headers.Authorization, "Bearer fixture-service");
    assert.equal(body.p_user, user);
    assert.equal(body.p_session, session);
    assert.equal(body.p_request, id);
    assert.equal(body.p_object_path, evidence.object_path);
    assert.equal(body.p_submitted_at, evidence.submitted_at);
    assert.match(body.p_sha256, /^[0-9a-f]{64}$/);
    const digests = await certificateDigests(facts, secret);
    assert.equal(body.p_semantic_digest, digests.semantic);
    assert.equal(body.p_secondary_digest, digests.reference);
    const approved = body.p_decision === "approved" && !options.duplicate;
    return Response.json({
      request: { ...row, status: approved ? "approved" : "changes_requested", review_note: options.duplicate ? "duplicate_certificate" : body.p_reason },
      wallet: { ...wallet, balance: approved ? 40 : 10 }, duplicate: options.duplicate ?? false, credited: approved,
    }, { status: options.settlementStatus ?? 200 });
  });
  const submit = (updates = {}) => handler(new Request("https://project.test/functions/v1/analyze-donation-evidence", {
    method: updates.method ?? "POST", signal: updates.signal,
    headers: { authorization: `Bearer ${updates.token ?? jwt}`, "content-type": updates.mime ?? "application/json" },
    ...(updates.method === "GET" ? {} : { body: updates.body ?? JSON.stringify({ evidence_id: id }) }),
  }));
  return { calls, submit };
}

const paths = calls => calls.map(call => call.path);
const settled = calls => calls.find(call => call.path === "/rest/v1/rpc/oi_coin_evidence_review");

test("settles an issued POSTECH certificate through the canonical account and service-only transaction", async () => {
  const { calls, submit } = setup();
  const response = await submit();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const result = await response.json();
  assert.equal(result.request.status, "approved");
  assert.equal(result.wallet.balance, 40);
  assert.equal(result.credited, true);
  assert.equal(result.authenticity_verified, false);
  assert.equal(result.holder_verified, false);
  const output = JSON.stringify(result);
  for (const privateValue of [certificate.donor_name, certificate.certificate_reference, secret, "fixture-service"]) assert.ok(!output.includes(privateValue));
  assert.equal(settled(calls).body.p_decision, "approved");
  assert.equal(paths(calls).filter(path => path === "/auth/v1/user").length, 2);
  assert.equal(paths(calls).indexOf("/rest/v1/rpc/oi_prepare_coin_evidence") < paths(calls).findIndex(path => path.includes("/storage/")), true);
});

for (const amount of [1, 100, 4999]) {
  test(`does not invent a minimum donation amount (${amount} KRW)`, () => {
    assert.equal(certificateDecision(parseCertificate({ ...certificate, amount }), new Date("2026-11-18T00:00:00Z")).decision, "approved");
  });
}

test("accepts PNG bytes with a matching signature without exposing a public file URL", async () => {
  const { calls, submit } = setup({ mime: "image/png", bytes: new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]) });
  assert.equal((await submit()).status, 200);
  assert.equal(paths(calls).some(path => path.includes("/sign/")), false);
});

for (const [name, facts, decision] of [
  ["another institution", { institution: "other", issuer_name: "Another University" }, "rejected"],
  ["SMS", { document_kind: "sms" }, "rejected"],
  ["transfer screenshot", { document_kind: "bank_transfer" }, "rejected"],
  ["pledge", { payment_state: "pledge_only" }, "rejected"],
  ["blank sample", { issued_document: "sample_or_application" }, "rejected"],
  ["cancelled donation", { payment_state: "cancelled" }, "rejected"],
  ["zero donation", { amount: 0 }, "rejected"],
  ["unreadable certificate", { readability: "unreadable" }, "needs_review"],
  ["conflicting amount", { visual_consistency: "conflicting" }, "needs_review"],
  ["conflicting numeric and written amount despite a clean AI verdict", { amount_in_words: 10000 }, "needs_review"],
  ["several certificates in one PDF", { transaction_count: "multiple" }, "needs_review"],
  ["uncertain issuer", { issuer_name: null }, "needs_review"],
  ["false POSTECH label", { issuer_name: "Different issuer" }, "needs_review"],
  ["future donation", { donation_date: "2099-01-01" }, "needs_review"],
  ["missing duplicate identity", { certificate_reference: null, donor_name: null }, "needs_review"],
]) {
  test(`does not auto-award ${name}`, async () => {
    const { calls, submit } = setup({ facts });
    const response = await submit();
    assert.equal(response.status, 200);
    assert.equal(settled(calls).body.p_decision, decision);
    assert.equal((await response.json()).credited, false);
  });
}

test("fingerprints certificates using server HMAC and normalizes equivalent POSTECH donor facts", async () => {
  const numbered = await certificateDigests(certificate, secret);
  assert.match(numbered.reference, /^[0-9a-f]{64}$/);
  assert.match(numbered.semantic, /^[0-9a-f]{64}$/);
  assert.deepEqual(await certificateDigests({ ...certificate, issuer_name: "POSTECH", certificate_reference: "cert 2026 000001" }, secret), numbered);
  const unnumbered = { ...certificate, certificate_reference: null, donor_name: "홍 길 동" };
  const digest = await certificateDigests(unnumbered, secret);
  assert.deepEqual(digest, await certificateDigests({ ...unnumbered, donor_name: "홍길동", issuer_name: "포스텍" }, secret));
  assert.notEqual(digest.semantic, (await certificateDigests({ ...unnumbered, amount: 2000 }, secret)).semantic);
  assert.notEqual(digest.semantic, (await certificateDigests(unnumbered, "d".repeat(64))).semantic);
  assert.equal((await certificateDigests({ ...unnumbered, donation_date: null }, secret)).semantic, null);
  assert.equal(certificateDecision(unnumbered).decision, "approved");
});

test("retains a common composite identity when a copy hides its certificate number", async () => {
  const full = await certificateDigests(certificate, secret);
  const cropped = await certificateDigests({ ...certificate, certificate_reference: null }, secret);
  assert.equal(full.semantic, cropped.semantic);
  assert.equal(cropped.reference, null);
  const distinct = await certificateDigests({ ...certificate, certificate_reference: "CERT-2026-000002" }, secret);
  assert.equal(full.semantic, distinct.semantic);
  assert.notEqual(full.reference, distinct.reference);
  // SQL compares composite identity when either side lacks a strong reference.
  assert.equal(certificateDecision({ ...certificate, donor_name: null }).decision, "needs_review");
});

test("honors the database duplicate decision without awarding a second certificate reward", async () => {
  const { submit } = setup({ duplicate: true });
  const result = await (await submit()).json();
  assert.equal(result.duplicate, true);
  assert.equal(result.credited, false);
  assert.equal(result.wallet.balance, 10);
  assert.equal(result.request.review_note, "duplicate_certificate");
});

for (const status of ["approved", "rejected", "changes_requested"]) {
  test(`replays a ${status} result without repeating AI or credit`, async () => {
    const { calls, submit } = setup({ row: { status, review_note: "duplicate_certificate" } });
    const result = await (await submit()).json();
    assert.equal(result.request.status, status);
    assert.equal(result.credited, false);
    assert.equal(result.duplicate, true);
    assert.ok(!paths(calls).includes("/v1/responses"));
    assert.ok(!paths(calls).includes("/rest/v1/rpc/oi_prepare_coin_evidence"));
  });
}

for (const [name, options, updates, status] of [
  ["anonymous session", { anonymous: true }, {}, 401],
  ["invalid auth", { authStatus: 401 }, {}, 401],
  ["unverified JWT session", {}, { token: "malformed" }, 401],
  ["missing object", { hidden: true }, {}, 404],
  ["another account", { row: { user_id: user } }, {}, 404],
  ["retired evidence", { row: { coin_verification: false } }, {}, 409],
  ["missing AI consent", { row: { coin_consent_version: null } }, {}, 409],
  ["path outside evidence request", { row: { object_path: `${account}/${id}/certificate.pdf` } }, {}, 409],
  ["path traversal", { row: { object_path: `${user}/${id}/..` } }, {}, 409],
  ["unsubmitted draft", { row: { status: "draft" } }, {}, 409],
  ["client supplied URL", {}, { body: JSON.stringify({ evidence_id: id, url: "https://external.test/file" }) }, 400],
  ["raw document request", {}, { mime: "application/pdf" }, 415],
  ["malformed JSON", {}, { body: "{" }, 400],
  ["oversized request", {}, { body: " ".repeat(1025) }, 413],
  ["invalid file signature", { bytes: "not PDF" }, {}, 415],
  ["unsupported MIME", { mime: "text/html" }, {}, 415],
  ["oversized file", { length: 10 * 1024 * 1024 + 1 }, {}, 413],
  ["database analysis lease", { prepareStatus: 409 }, {}, 409],
  ["database account quota", { prepareStatus: 429 }, {}, 429],
]) {
  test(`blocks ${name} before the provider`, async () => {
    const { calls, submit } = setup(options);
    assert.equal((await submit(updates)).status, status);
    assert.ok(!paths(calls).includes("/v1/responses"));
    assert.equal(settled(calls), undefined);
  });
}

for (const [name, options, status] of [
  ["provider rate limit", { providerStatus: 429 }, 429],
  ["provider failure", { providerStatus: 500 }, 502],
  ["model refusal", { refusal: true }, 422],
  ["incomplete model response", { incomplete: true }, 502],
  ["invented approval field", { facts: { approved: true } }, 502],
  ["invalid extracted date", { facts: { donation_date: "2026-02-30" } }, 502],
  ["expired user session", { failReauth: true }, 401],
  ["merged account during analysis", { mergeDuringAnalysis: true }, 409],
  ["changed file snapshot", { changedRow: { object_path: `${user}/${id}/replacement.pdf` } }, 409],
  ["reviewed during analysis", { changedRow: { status: "approved" } }, 409],
]) {
  test(`does not settle after ${name}`, async () => {
    const { calls, submit } = setup(options);
    assert.equal((await submit()).status, status);
    assert.equal(settled(calls), undefined);
  });
}

test("returns a settlement conflict instead of reporting credit", async () => {
  const { submit } = setup({ settlementStatus: 409 });
  const response = await submit();
  assert.equal(response.status, 409);
  assert.equal((await response.json()).credited, undefined);
});

test("cancellation withholds settlement and releases the local in-flight slot", async () => {
  const abort = new AbortController();
  const { calls, submit } = setup({ abort });
  assert.equal((await submit({ signal: abort.signal })).status, 499);
  assert.equal(settled(calls), undefined);
  assert.equal((await submit()).status, 200);
});

test("concurrent retries for one pending certificate cannot start another provider request", async () => {
  let release;
  const holdProvider = new Promise(resolve => { release = resolve; });
  const { calls, submit } = setup({ holdProvider });
  const first = submit();
  while (!paths(calls).includes("/v1/responses")) await new Promise(resolve => setImmediate(resolve));
  assert.equal((await submit()).status, 429);
  release();
  assert.equal((await first).status, 200);
  assert.equal(paths(calls).filter(path => path === "/v1/responses").length, 1);
});

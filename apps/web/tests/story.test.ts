import { test } from "node:test";
import assert from "node:assert/strict";
import { storyInput, storyText, byteLength } from "../src/lib/story";
import { correctPassword, makeSession, validSession, checkOrigin, boundedBody, HttpError } from "../src/lib/security";
process.env.ADMIN_PASSWORD = "test-only-password-not-for-production";
process.env.SESSION_SECRET = "test-only-session-secret-at-least-32-characters";
const input = { matNumber: 1, matSize: "small", displayName: "운영팀", story: "이야기", paymentVerified: false, published: false };
test("anonymous or whitespace names cannot be registered", () => {
  for (const name of ["", "   ", "a".repeat(41)]) assert.equal(storyInput.safeParse({ ...input, displayName: name }).success, false);
});
test("story byte limit handles UTF-8 including emoji", () => {
  assert.equal(storyInput.safeParse({ ...input, story: "🧺".repeat(100) }).success, true);
  assert.equal(storyText.safeParse("a".repeat(1000)).success, true);
  assert.equal(storyText.safeParse("a".repeat(1001)).success, false);
  assert.equal(storyText.safeParse("\uac00".repeat(333) + "a").success, true);
  assert.equal(storyText.safeParse("\uac00".repeat(333) + "ab").success, false);
  assert.equal(storyText.safeParse("🧺".repeat(250)).success, true);
  assert.equal(storyText.safeParse("🧺".repeat(250) + "a").success, false);
  assert.equal(storyText.safeParse("   ").success, false);
  assert.equal(byteLength("\ud83e\uddfa"), 4);
});
test("publication requires verified payment and valid mat type", () => {
  assert.equal(storyInput.safeParse({ ...input, published: true }).success, false);
  assert.equal(storyInput.safeParse({ ...input, published: true, paymentVerified: true }).success, true);
  assert.equal(storyInput.safeParse({ ...input, matSize: "other" }).success, false);
});
test("session expiry, tamper rejection and password rotation", () => {
  const now = 1790000000000; const token = makeSession(now);
  assert.equal(validSession(token, now), true);
  assert.equal(validSession(token, now + 28800001), false);
  assert.equal(validSession(token + "x", now), false);
  assert.equal(validSession("forged", now), false);
  assert.equal(correctPassword("wrong"), false);
  process.env.ADMIN_PASSWORD = "rotated-test-only-password";
  assert.equal(validSession(token, now), false);
  process.env.ADMIN_PASSWORD = "test-only-password-not-for-production";
});
test("cross-origin and missing-origin mutations are rejected", () => {
  const previous = process.env.APP_ORIGIN;
  try {
    process.env.APP_ORIGIN = "http://localhost:3000";
    assert.throws(() => checkOrigin(new Request("http://localhost:3000/api", { headers: { origin: "https://evil.invalid" } })), HttpError);
    assert.throws(() => checkOrigin(new Request("http://localhost:3000/api")), HttpError);
    checkOrigin(new Request("http://localhost:3000/api", { headers: { origin: "http://localhost:3000" } }));
    process.env.APP_ORIGIN = "https://pilot.example";
    checkOrigin(new Request("http://internal:3000/api", { headers: { origin: "https://pilot.example" } }));
    assert.throws(() => checkOrigin(new Request("http://internal:3000/api", { headers: { origin: "http://internal:3000" } })), HttpError);
  } finally {
    if (previous === undefined) delete process.env.APP_ORIGIN;
    else process.env.APP_ORIGIN = previous;
  }
});
test("streamed request bodies cannot bypass upload limits", async () => {
  await assert.rejects(() => boundedBody(new Request("http://localhost/api", { method: "POST", body: "12345" }), 4), HttpError);
});

test("nine-character shared passwords support login and sessions", () => {
  const previous = process.env.ADMIN_PASSWORD;
  try {
    process.env.ADMIN_PASSWORD = "test-only";
    assert.equal(correctPassword("test-only"), true);
    assert.equal(correctPassword("incorrect"), false);
    assert.equal(validSession(makeSession()), true);
    process.env.ADMIN_PASSWORD = "short";
    assert.throws(() => correctPassword("short"), HttpError);
  } finally {
    process.env.ADMIN_PASSWORD = previous;
  }
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { appOrigin, officialDonationUrl, loginDestination } from "../src/lib/web-config";
test("official donation links reject insecure, lookalike and credential URLs", () => {
  for (const url of ["http://postech.ac.kr/give", "https://postech.ac.kr.evil.test", "https://evil.test", "https://user:pass@postech.ac.kr", "javascript:alert(1)", "invalid"]) assert.equal(officialDonationUrl(url), null);
  assert.equal(officialDonationUrl("https://giving.postech.ac.kr/give"), "https://giving.postech.ac.kr/give");
});
test("login returns only to supported local destinations", () => {
  assert.equal(loginDestination("/donate"), "/donate");
  for (const value of ["https://evil.test", "//evil.test", "/\\evil.test", "//donate", null]) assert.equal(loginDestination(value), "/");
});
test("app origin must be exact HTTPS or local development origin", () => {
  assert.equal(appOrigin("http://127.0.0.1:4316"), "http://127.0.0.1:4316");
  assert.equal(appOrigin("https://example.org"), "https://example.org");
  for (const value of ["invalid", "https://example.org/", "https://user:pass@example.org", "http://example.org"]) assert.equal(appOrigin(value), null);
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { activityExclusionToken, validActivityExclusion, validSession, makeSession } from "../src/lib/security";

process.env.ADMIN_PASSWORD = "test-only-admin-password";
process.env.SESSION_SECRET = "test-only-session-secret-at-least-32-characters";

test("activity exclusion cannot grant admin access and survives password/session expiry", () => {
  const token = activityExclusionToken();
  assert.equal(validActivityExclusion(token), true);
  assert.equal(validSession(token), false);
  assert.equal(validActivityExclusion(makeSession()), false);
  for (const bad of [undefined, "1", "forged", token + "x", "0".repeat(64)]) assert.equal(validActivityExclusion(bad), false);
  process.env.ADMIN_PASSWORD = "rotated-test-only-admin-password";
  assert.equal(validActivityExclusion(token), true);
  process.env.SESSION_SECRET = "rotated-test-only-secret-at-least-32-characters";
  assert.equal(validActivityExclusion(token), false);
});

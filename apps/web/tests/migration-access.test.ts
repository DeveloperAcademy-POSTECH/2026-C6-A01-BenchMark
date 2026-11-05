import { test } from "node:test";
import assert from "node:assert/strict";
import { requireMigration } from "../lib/migration";

test("migration export and import require both an explicit window and a separate secret", () => {
  const previousEnabled = process.env.MIGRATION_ENABLED;
  const previousToken = process.env.MIGRATION_TOKEN;
  const token = "test-only-migration-key-at-least-32-characters";
  const request = (method = "GET", value = token) => new Request("https://test.local/api/migration", {
    method, headers: { "x-migration-token": value },
  });
  try {
    delete process.env.MIGRATION_ENABLED;
    process.env.MIGRATION_TOKEN = token;
    assert.throws(() => requireMigration(request()), { status: 404 });
    process.env.MIGRATION_ENABLED = "true";
    delete process.env.MIGRATION_TOKEN;
    assert.throws(() => requireMigration(request()), { status: 404 });
    process.env.MIGRATION_TOKEN = "short";
    assert.throws(() => requireMigration(request()), { status: 404 });
    process.env.MIGRATION_TOKEN = token;
    for (const value of ["", "wrong", "x".repeat(257)]) {
      assert.throws(() => requireMigration(request("GET", value)), { status: 404 });
      assert.throws(() => requireMigration(request("POST", value)), { status: 404 });
    }
    requireMigration(request());
    requireMigration(request("POST"));
    for (const method of ["DELETE", "PUT", "PATCH"]) assert.throws(() => requireMigration(request(method)), { status: 404 });
    process.env.MIGRATION_ENABLED = "false";
    assert.throws(() => requireMigration(request()), { status: 404 });
  } finally {
    if (previousEnabled === undefined) delete process.env.MIGRATION_ENABLED;
    else process.env.MIGRATION_ENABLED = previousEnabled;
    if (previousToken === undefined) delete process.env.MIGRATION_TOKEN;
    else process.env.MIGRATION_TOKEN = previousToken;
  }
});

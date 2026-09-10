import test from "node:test";
import assert from "node:assert/strict";
import { database } from "../src/lib/db";
import { saveRegistration } from "../src/lib/save-registration";
const pool = database();
const input = { name: "테스트", phone: "01000001234", consent: true as const, formVersion: 1 as const };
test("PostgreSQL persistence, concurrent duplicates, expiration and rate limiting", async () => {
  if (process.env.ALLOW_TEST_DATABASE_RESET !== "yes") throw new Error("Use a disposable test database with ALLOW_TEST_DATABASE_RESET=yes");
  try {
    await pool.query("TRUNCATE registrations, registration_rate_limits");
    assert.equal(await saveRegistration(pool, input, 7), "accepted");
    await Promise.all(Array.from({ length: 8 }, () => saveRegistration(pool, { ...input, name: "교체 금지" }, 7)));
    let result = await pool.query("SELECT name, form_version, answers, expires_at > created_at AS expires FROM registrations");
    assert.equal(result.rowCount, 1);
    assert.equal(result.rows[0].name, "테스트");
    assert.equal(result.rows[0].form_version, 1);
    assert.deepEqual(result.rows[0].answers, {});
    assert.equal(result.rows[0].expires, true);
    await pool.query("UPDATE registrations SET expires_at = now() - interval '1 day'");
    await saveRegistration(pool, { ...input, phone: "01000004321" }, 7);
    result = await pool.query("SELECT phone FROM registrations");
    assert.equal(result.rowCount, 1);
    assert.equal(result.rows[0].phone, "01000004321");
    await pool.query("UPDATE registration_rate_limits SET attempts = 60");
    assert.equal(await saveRegistration(pool, input, 7), "limited");
    assert.equal((await pool.query("SELECT 1 FROM registrations WHERE phone=$1", [input.phone])).rowCount, 0);
  } finally {
    await pool.query("TRUNCATE registrations, registration_rate_limits");
    await pool.end();
  }
});

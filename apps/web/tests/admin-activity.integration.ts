import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { database } from "../src/lib/db";
import { activityExclusionCookie, makeSession, sessionCookie } from "../src/lib/security";

const base = process.env.TEST_BASE_URL || "http://127.0.0.1:4314";
if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated benchmark_mat_test database only.");
const pool = database();
const sessionId = randomUUID();
function send(cookie = "", origin = base) {
  const event = { id: randomUUID(), visitId: randomUUID(), sessionId, name: "page_view", occurredAt: new Date().toISOString(), path: "/stories", properties: {} };
  return fetch(`${base}/api/activity`, { method: "POST", headers: { origin, cookie, "Content-Type": "application/json" }, body: JSON.stringify({ events: [event] }) });
}
function cookieFrom(response: Response, name: string) {
  return response.headers.getSetCookie().find(value => value.startsWith(`${name}=`));
}
function login(password: string) {
  return fetch(`${base}/api/admin/session`, { method: "POST", headers: { origin: base, "Content-Type": "application/json" }, body: JSON.stringify({ password }) });
}

test("admin login history excludes persistence after logout/expiry, including legacy sessions", async () => {
  try {
    assert.deepEqual(await (await send()).json(), { accepted: 1 });
    const failed = await login("wrong-password");
    assert.equal(failed.status, 401);
    assert.equal(cookieFrom(failed, activityExclusionCookie), undefined);
    const loggedIn = await login(process.env.ADMIN_PASSWORD!);
    assert.equal(loggedIn.status, 200);
    const marker = cookieFrom(loggedIn, activityExclusionCookie)!;
    assert.ok(marker);
    assert.match(marker, /HttpOnly/i);
    assert.match(marker, /SameSite=lax/i);
    assert.match(marker, /Max-Age=34560000/i);
    assert.match(marker, /Path=\//i);
    const history = marker.split(";")[0];
    const auth = cookieFrom(loggedIn, sessionCookie)!.split(";")[0];
    assert.deepEqual(await (await send(`${auth}; ${history}`)).json(), { accepted: 0 });
    const logout = await fetch(`${base}/api/admin/session`, { method: "DELETE", headers: { origin: base, cookie: `${auth}; ${history}` } });
    assert.equal(logout.status, 200);
    assert.match(cookieFrom(logout, activityExclusionCookie)!, /Max-Age=34560000/i);
    const afterLogout = await send(history);
    assert.deepEqual(await afterLogout.json(), { accepted: 0 });
    assert.equal(afterLogout.headers.get("cache-control"), "private, no-store");
    const expired = `${sessionCookie}=${makeSession(Date.now() - 9 * 60 * 60 * 1000)}`;
    assert.deepEqual(await (await send(`${expired}; ${history}`)).json(), { accepted: 0 });
    assert.equal((await fetch(`${base}/api/admin/activity`, { headers: { cookie: history } })).status, 401);
    const legacy = await send(auth);
    assert.deepEqual(await legacy.json(), { accepted: 0 });
    assert.ok(cookieFrom(legacy, activityExclusionCookie));
    const legacyLogout = await fetch(`${base}/api/admin/session`, { method: "DELETE", headers: { origin: base, cookie: auth } });
    assert.ok(cookieFrom(legacyLogout, activityExclusionCookie));
    assert.equal((await send(history, "https://evil.invalid")).status, 403);
    assert.deepEqual(await (await send(`${activityExclusionCookie}=forged`)).json(), { accepted: 1 });
    assert.deepEqual(await (await send(expired)).json(), { accepted: 1 });
    assert.deepEqual(await (await send()).json(), { accepted: 1 });
    assert.equal((await pool.query("SELECT count(*)::int AS n FROM mat_activity_events WHERE session_id=$1", [sessionId])).rows[0].n, 4);
  } finally {
    await pool.query("DELETE FROM mat_activity_events WHERE session_id=$1", [sessionId]);
    await pool.query("DELETE FROM mat_rate_limits WHERE key=$1", [`activity:session:${sessionId}`]);
    await pool.end();
  }
});

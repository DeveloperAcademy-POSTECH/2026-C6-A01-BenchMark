import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { database } from "../src/lib/db";
import { pruneActivity } from "../src/lib/activity-store";

const base = process.env.TEST_BASE_URL || "http://127.0.0.1:4314";
if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated benchmark_mat_test database only.");
const pool = database();
const sessionId = randomUUID();
const visitId = randomUUID();
function event(changes: Record<string, unknown> = {}) {
  return { id: randomUUID(), visitId, sessionId, name: "page_view", occurredAt: new Date().toISOString(), path: "/", properties: {}, ...changes };
}
async function send(events: unknown[], origin = base) {
  return fetch(`${base}/api/activity`, { method: "POST", headers: { origin, "Content-Type": "application/json" }, body: JSON.stringify({ events }) });
}
test("activity persistence, retry deduplication, validation, limits, admin filters, pagination, CSV and retention", async () => {
  let cookie = "";
  try {
    for (const format of ["json", "csv"]) assert.equal((await fetch(`${base}/api/admin/activity?format=${format}`)).status, 401);
    const view = event();
    assert.equal((await send([view], "https://evil.invalid")).status, 403);
    for (const response of await Promise.all(Array.from({ length: 5 }, () => send([view])))) assert.equal(response.status, 200);
    assert.equal((await send([event()])).status, 200);
    assert.equal((await pool.query("SELECT count(*)::int AS n FROM mat_activity_events WHERE session_id=$1", [sessionId])).rows[0].n, 1);
    const scroll = event({ name: "scroll_depth", properties: { percent: 50 } });
    assert.equal((await send([scroll, { ...scroll, id: randomUUID() }])).status, 200);
    assert.equal((await pool.query("SELECT count(*)::int AS n FROM mat_activity_events WHERE session_id=$1", [sessionId])).rows[0].n, 2);
    assert.equal((await send([event({ name: "photo_capture_success", path: "/camera" })])).status, 200);
    for (const bad of [event({ phone: "01000009999" }), event({ properties: { story: "private" } }), event({ path: "/reserve?phone=01000009999" }), event({ name: "donation_success" }), event({ occurredAt: "2000-01-01T00:00:00.000Z" }), event({ storyId: randomUUID() }), event({ name: "scroll_depth", properties: { percent: 101 } })]) assert.equal((await send([bad])).status, 400);
    assert.equal((await send(Array.from({ length: 21 }, () => event()))).status, 400);
    assert.equal((await send([event({ padding: "x".repeat(20000) })])).status, 413);
    await pool.query("INSERT INTO mat_rate_limits(key,window_start,attempts) VALUES($1,now(),120) ON CONFLICT(key) DO UPDATE SET attempts=120,window_start=now()", [`activity:session:${sessionId}`]);
    assert.equal((await send([event()])).status, 429);
    await pool.query("DELETE FROM mat_rate_limits WHERE key=$1", [`activity:session:${sessionId}`]);
    const login = await fetch(`${base}/api/admin/session`, { method: "POST", headers: { origin: base }, body: JSON.stringify({ password: process.env.ADMIN_PASSWORD }) });
    assert.equal(login.status, 200); cookie = login.headers.get("set-cookie")!.split(";")[0];
    const headers = { cookie };
    const from = new Date(Date.now() - 60000).toISOString();
    const queried = await fetch(`${base}/api/admin/activity?name=scroll_depth&path=%2F&from=${from}`, { headers });
    assert.equal(queried.status, 200); assert.equal(queried.headers.get("cache-control"), "private, no-store");
    const results = await queried.json(); assert.ok(results.rows.some((r: { session_id: string }) => r.session_id === sessionId));
    assert.ok(results.rows.every((r: { name: string }) => r.name === "scroll_depth"));
    assert.equal((await fetch(`${base}/api/admin/activity?from=invalid`, { headers })).status, 400);
    assert.equal((await fetch(`${base}/api/admin/activity?path=%2Fadmin`, { headers })).status, 400);
    assert.equal((await fetch(`${base}/api/admin/activity?storyId=${randomUUID()}`, { headers }).then(r => r.json())).rows.length, 0);
    const csv = await fetch(`${base}/api/admin/activity?format=csv&name=scroll_depth`, { headers });
    assert.equal(csv.status, 200); assert.ok(csv.headers.get("content-disposition")?.includes("attachment"));
    const text = await csv.text(); assert.ok(text.includes(sessionId)); assert.equal(text.includes("01000009999"), false);
    // Same timestamp exercises the UUID tie-breaker in keyset pagination.
    const stamp = new Date(Date.now() - 1000).toISOString();
    await pool.query("INSERT INTO mat_activity_events(id,visit_id,session_id,name,occurred_at,path,properties) SELECT gen_random_uuid(),gen_random_uuid(),$1,'active_time',$2,'/','{\"milliseconds\":1}'::jsonb FROM generate_series(1,101)", [sessionId, stamp]);
    const first = await fetch(`${base}/api/admin/activity?name=active_time`, { headers }).then(r => r.json());
    assert.equal(first.rows.length, 100); assert.ok(first.next);
    const second = await fetch(`${base}/api/admin/activity?name=active_time&${new URLSearchParams(first.next)}`, { headers }).then(r => r.json());
    assert.equal(second.rows.length, 1); assert.equal(second.next, null);
    assert.equal(new Set([...first.rows, ...second.rows].map(r => r.id)).size, 101);
    await pool.query("INSERT INTO mat_activity_events(id,visit_id,session_id,name,occurred_at,path,properties) VALUES($1,$2,$3,'page_view',now()-interval '31 days','/','{}')", [randomUUID(), randomUUID(), sessionId]);
    await pruneActivity();
    assert.equal((await pool.query("SELECT count(*)::int AS n FROM mat_activity_events WHERE occurred_at <= now()-interval '30 days'")).rows[0].n, 0);
    await pool.query("INSERT INTO mat_activity_events(id,visit_id,session_id,name,occurred_at,path,properties) SELECT gen_random_uuid(),gen_random_uuid(),$1,'photo_selected',now(),'/reserve','{}'::jsonb FROM generate_series(1,5001)", [sessionId]);
    assert.equal((await fetch(`${base}/api/admin/activity?format=csv&name=photo_selected`, { headers })).status, 400);
  } finally {
    await pool.query("DELETE FROM mat_activity_events WHERE session_id=$1", [sessionId]);
    await pool.query("DELETE FROM mat_rate_limits WHERE key=$1", [`activity:session:${sessionId}`]);
    await pool.end();
  }
});

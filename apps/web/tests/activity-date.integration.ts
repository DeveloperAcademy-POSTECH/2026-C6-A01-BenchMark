import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { database } from "../src/lib/db";
import { activityKoreaTime } from "../src/lib/activity";
import { makeSession, sessionCookie } from "../src/lib/security";

if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated benchmark_mat_test database only.");
const base = process.env.TEST_BASE_URL || "http://127.0.0.1:4314";
const pool = database();
test("Korean day boundaries, pagination, CSV, filters, invalid dates and authorization", async () => {
  const session = randomUUID();
  const story = randomUUID();
  const day = activityKoreaTime(new Date(Date.now() - 3 * 86400000).toISOString()).slice(0, 10);
  const start = Date.parse(`${day}T00:00:00+09:00`);
  const headers = { cookie: `${sessionCookie}=${makeSession()}` };
  const params = new URLSearchParams({ date: day, path: `/stories/${story}`, name: "active_time" });
  const get = (p: URLSearchParams) => fetch(`${base}/api/admin/activity?${p}`, { headers });
  try {
    for (const offset of [-1, 0, 86399999, 86400000]) {
      await pool.query("INSERT INTO mat_activity_events(id,visit_id,session_id,name,occurred_at,path,properties) VALUES($1,$2,$3,'active_time',$4,$5,'{\"milliseconds\":1}')", [randomUUID(), randomUUID(), session, new Date(start + offset), `/stories/${story}`]);
    }
    await pool.query("INSERT INTO mat_activity_events(id,visit_id,session_id,name,occurred_at,path,properties) SELECT gen_random_uuid(),gen_random_uuid(),$1,'active_time',$2,$3,'{\"milliseconds\":1}'::jsonb FROM generate_series(1,99)", [session, new Date(start + 1000), `/stories/${story}`]);
    const first = await (await get(params)).json();
    assert.equal(first.rows.length, 100);
    assert.ok(first.next);
    const secondParams = new URLSearchParams(params);
    for (const [key, value] of Object.entries(first.next)) secondParams.set(key, String(value));
    const second = await (await get(secondParams)).json();
    assert.equal(second.rows.length, 1);
    const rows = [...first.rows, ...second.rows];
    assert.equal(new Set(rows.map(r => r.id)).size, 101);
    assert.equal(rows.at(-1).occurred_at, new Date(start).toISOString());
    assert.equal(rows[0].occurred_at, new Date(start + 86399999).toISOString());
    params.set("format", "csv");
    const csv = await (await get(params)).text();
    assert.equal(csv.trim().split("\r\n").length, 102);
    for (const row of rows) assert.ok(csv.includes(row.id));
    assert.ok(csv.includes(`${day}T00:00:00.000+09:00`));
    assert.ok(csv.includes(`${day}T23:59:59.999+09:00`));
    for (const format of ["json", "csv"]) {
      params.set("format", format);
      assert.equal((await fetch(`${base}/api/admin/activity?${params}`)).status, 401);
      for (const invalid of ["2026-02-30", "2026-13-01", "not-a-date"]) {
        const bad = new URLSearchParams(params); bad.set("date", invalid);
        assert.equal((await get(bad)).status, 400);
      }
      const mixed = new URLSearchParams(params); mixed.set("from", new Date(start).toISOString());
      assert.equal((await get(mixed)).status, 400);
    }
    params.set("format", "json"); params.set("name", "scroll_depth");
    assert.deepEqual((await (await get(params)).json()).rows, []);
  } finally {
    await pool.query("DELETE FROM mat_activity_events WHERE session_id=$1", [session]);
    await pool.end();
  }
});

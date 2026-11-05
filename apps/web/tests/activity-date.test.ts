import { test } from "node:test";
import assert from "node:assert/strict";
import { activityKoreaTime } from "../lib/activity";
test("Korean date formatting crosses day, month, leap-day and year boundaries", () => {
  for (const [utc, expected] of [
    ["2026-09-16T14:59:59.999Z", "2026-09-16T23:59:59.999+09:00"],
    ["2026-09-16T15:00:00.000Z", "2026-09-17T00:00:00.000+09:00"],
    ["2026-12-31T15:00:00.000Z", "2027-01-01T00:00:00.000+09:00"],
    ["2028-02-28T15:00:00.000Z", "2028-02-29T00:00:00.000+09:00"],
  ]) assert.equal(activityKoreaTime(utc), expected);
});

import { Miniflare } from "miniflare";
import { randomUUID } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { database } from "../lib/db";
import { runWithStorageBindings } from "../lib/sites-storage";
import { queryActivity } from "../lib/activity-store";
import { csvActivity } from "../lib/activity";

test("D1 Korean-day queries preserve midnight bounds, pagination, CSV and invalid-filter rejection", { timeout: 60000 }, async () => {
  const mf = new Miniflare({ modules: true, script: "export default { fetch(){ return new Response('test'); } }", compatibilityDate: "2026-05-15", d1Databases: ["DB"], r2Buckets: ["BUCKET"] });
  try {
    const db = await mf.getD1Database("DB");
    const bucket = await mf.getR2Bucket("BUCKET");
    const directory = new URL("../drizzle/", import.meta.url);
    for (const file of (await readdir(directory)).filter(file => file.endsWith(".sql")).sort()) {
      for (const sql of (await readFile(new URL(file, directory), "utf8")).split("--> statement-breakpoint")) {
        if (sql.trim()) await db.prepare(sql).run();
      }
    }
    await runWithStorageBindings({ DB: db as unknown as D1Database, BUCKET: bucket as unknown as R2Bucket }, async () => {
      const date = activityKoreaTime(new Date(Date.now() - 86400000).toISOString()).slice(0, 10);
      const start = new Date(`${date}T00:00:00+09:00`).getTime();
      const ids: string[] = [];
      for (const offset of [-1, ...Array.from({ length: 101 }, (_, i) => i), 86400000]) {
        const id = randomUUID();
        if (offset >= 0 && offset < 86400000) ids.push(id);
        await database().query("INSERT INTO mat_activity_events(id,visit_id,session_id,name,occurred_at,path,properties) VALUES($1,$2,$3,'page_view',$4,'/',$5)", [id, randomUUID(), randomUUID(), new Date(start + offset).toISOString(), {}]);
      }
      const first = await queryActivity(new URLSearchParams({ date }));
      assert.equal(first.rows.length, 100);
      assert.ok(first.next);
      const second = await queryActivity(new URLSearchParams({ date, ...first.next }));
      assert.equal(second.rows.length, 1);
      assert.equal(second.next, null);
      assert.deepEqual(new Set([...first.rows, ...second.rows].map(row => row.id)), new Set(ids));
      const csv = await queryActivity(new URLSearchParams({ date, format: "csv" }));
      assert.equal(csv.rows.length, 101);
      assert.match(csvActivity(csv.rows), /occurred_date_kst/);
      for (const params of <Record<string, string>[]>[{ date, from: new Date(start).toISOString() }, { date: "2026-02-30" }, { date, cursorTime: new Date(start).toISOString() }]) {
        await assert.rejects(() => queryActivity(new URLSearchParams(params)), /조건|일자/);
      }
    });
  } finally { await mf.dispose(); }
});

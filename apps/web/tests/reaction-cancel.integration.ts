import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { database } from "../src/lib/db";
import { reactionKinds } from "../src/lib/story";
const base = process.env.TEST_BASE_URL || "http://127.0.0.1:4314";
if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
const pool = database();
test("reaction removal is repeatable, private to the device and publication-scoped", async () => {
  const id = randomUUID(); const deviceId = randomUUID(); const other = randomUUID();
  const send = (action: string, kind: string, device = deviceId) => fetch(`${base}/api/stories/${id}/reaction`, { method: "POST", headers: { origin: base, "Content-Type": "application/json" }, body: JSON.stringify({ action, kind, deviceId: device }) });
  try {
    await pool.query("INSERT INTO mat_stories(id,mat_number,mat_size,display_name,story,photo,payment_verified,published) VALUES($1,9920,'small','검증','검증',$2,true,true)", [id, Buffer.from("test-only")]);
    for (const kind of reactionKinds) {
      assert.equal((await send("react", kind)).status, 200);
      assert.equal((await send("react", kind, other)).status, 200);
      const removals = await Promise.all(Array.from({ length: 4 }, () => send("remove", kind)));
      for (const response of removals) {
        assert.equal(response.status, 200);
        const result = await response.json();
        assert.equal(result.counts[kind], 1);
        assert.equal(result.selected.includes(kind), false);
      }
      const restored = await send("react", kind).then(r => r.json());
      assert.equal(restored.counts[kind], 2);
      assert.ok(restored.selected.includes(kind));
    }
    const otherState = await send("status", "like", other).then(r => r.json());
    assert.equal(otherState.selected.length, 4);
    assert.equal((await send("remove", "invalid")).status, 400);
    await pool.query("UPDATE mat_stories SET published=false WHERE id=$1", [id]);
    assert.equal((await send("remove", "like")).status, 404);
    assert.equal((await pool.query("SELECT count(*)::int AS count FROM mat_reactions WHERE story_id=$1", [id])).rows[0].count, 8);
  } finally {
    await pool.query("DELETE FROM mat_stories WHERE id=$1", [id]);
    await pool.end();
  }
});

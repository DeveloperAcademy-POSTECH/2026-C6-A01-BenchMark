import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import sharp from "sharp";
import { database } from "../src/lib/db";

const base = process.env.TEST_BASE_URL || "http://127.0.0.1:4314";
if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated benchmark_mat_test database only.");
const pool = database();
const ids: string[] = [];
let cookie = "";
const photo = await sharp({ create: { width: 800, height: 600, channels: 3, background: "#e7dfbb" } }).jpeg().toBuffer();
function fields(changes: Record<string, string> = {}, includePhoto = true) {
  const form = new FormData();
  for (const [key, value] of Object.entries({ matNumber: "9901", matSize: "small", displayName: "검증용 운영팀", story: "검증용 이야기입니다.", paymentVerified: "false", published: "false", ...changes })) form.set(key, value);
  if (includePhoto) form.set("photo", new Blob([new Uint8Array(photo)], { type: "image/jpeg" }), "test.jpg");
  return form;
}
async function send(path: string, method: string, body?: BodyInit, auth = true, origin = base) {
  return fetch(base + path, { method, headers: { origin, ...(auth ? { cookie } : {}) }, body, redirect: "manual" });
}
test("real API and PostgreSQL enforce publication, auth, image rules, uniqueness and revision conflicts", async () => {
  try {
    assert.equal((await send("/api/admin/stories", "POST", fields(), false)).status, 401);
    assert.equal((await send("/api/admin/session", "POST", JSON.stringify({ password: "incorrect" }), false)).status, 401);
    const login = await send("/api/admin/session", "POST", JSON.stringify({ password: process.env.ADMIN_PASSWORD }), false);
    assert.equal(login.status, 200); cookie = login.headers.get("set-cookie")!.split(";")[0];
    assert.ok(login.headers.get("set-cookie")?.includes("HttpOnly"));
    assert.equal((await send("/api/admin/stories", "POST", fields(), true, "https://evil.invalid")).status, 403);
    assert.equal((await send("/api/admin/stories", "POST", fields({ displayName: " " }))).status, 400);
    assert.equal((await send("/api/admin/stories", "POST", fields({ story: "가".repeat(101) }))).status, 400);
    assert.equal((await send("/api/admin/stories", "POST", fields({ published: "true" }))).status, 400);
    const badPhoto = fields(); badPhoto.set("photo", new Blob(["<svg onload='alert(1)'></svg>"], { type: "image/jpeg" }), "fake.jpg");
    assert.equal((await send("/api/admin/stories", "POST", badPhoto)).status, 400);
    const created = await send("/api/admin/stories", "POST", fields()); assert.equal(created.status, 201);
    const { id } = await created.json(); ids.push(id);
    assert.equal((await send("/api/admin/stories", "POST", fields())).status, 409);
    assert.equal((await fetch(`${base}/api/stories/${id}/photo`)).status, 404);
    assert.equal((await fetch(`${base}/api/stories/${id}/photo`, { headers: { cookie } })).status, 200);
    const draftPage = await (await fetch(`${base}/stories/${id}`)).text(); assert.equal(draftPage.includes("검증용 이야기입니다."), false);
    assert.equal((await send(`/api/stories/${id}/reaction`, "POST", JSON.stringify({ deviceId: randomUUID(), action: "react" }), false)).status, 404);
    const publish = await send(`/api/admin/stories/${id}`, "PUT", fields({ revision: "1", paymentVerified: "true", published: "true" }, false)); assert.equal(publish.status, 200);
    const image = await fetch(`${base}/api/stories/${id}/photo`); assert.equal(image.status, 200); assert.equal(image.headers.get("cache-control"), "private, no-store");
    const deviceId = randomUUID();
    const parallel = await Promise.all(Array.from({ length: 12 }, () => send(`/api/stories/${id}/reaction`, "POST", JSON.stringify({ deviceId, action: "react" }), false)));
    for (const response of parallel) assert.equal(response.status, 200);
    assert.equal((await pool.query("SELECT count(*)::int AS count FROM mat_reactions WHERE story_id=$1", [id])).rows[0].count, 1);
    const nextDevice = await send(`/api/stories/${id}/reaction`, "POST", JSON.stringify({ deviceId: randomUUID(), action: "react" }), false);
    assert.equal((await nextDevice.json()).count, 2);
    assert.equal((await send(`/api/admin/stories/${id}`, "PUT", fields({ revision: "1" }, false))).status, 409);
    assert.equal((await send(`/api/admin/stories/${id}`, "PUT", fields({ revision: "2", matSize: "large" }, false))).status, 200);
    assert.equal((await fetch(`${base}/api/stories/${id}/photo`)).status, 404);
    assert.equal((await send(`/api/admin/stories/${id}`, "DELETE", JSON.stringify({ revision: 2 }))).status, 409);
    assert.equal((await send(`/api/admin/stories/${id}`, "DELETE", JSON.stringify({ revision: 3 }))).status, 200);
    assert.equal((await pool.query("SELECT count(*)::int AS count FROM mat_reactions WHERE story_id=$1", [id])).rows[0].count, 0);
    assert.equal((await send("/api/admin/session", "DELETE")).status, 200);
  } finally {
    for (const id of ids) await pool.query("DELETE FROM mat_stories WHERE id=$1", [id]);
    await pool.end();
  }
});

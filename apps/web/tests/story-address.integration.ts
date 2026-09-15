import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import sharp from "sharp";
import { database } from "../src/lib/db";
const base = process.env.TEST_BASE_URL || "http://127.0.0.1:4314";
if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
const pool = database();
test("same-mat stories have distinct permanent addresses and isolated visibility", async () => {
  const ids: string[] = [];
  const photo = await sharp({ create: { width: 20, height: 20, channels: 3, background: "#eee" } }).jpeg().toBuffer();
  let cookie = "";
  const send = (path: string, method: string, body?: BodyInit) => fetch(base + path, { method, headers: { origin: base, cookie }, body });
  function form(title: string, revision?: string, published = "true") {
    const f = new FormData();
    for (const [key, value] of Object.entries({ matNumber: "9910", matSize: "small", displayName: "주소 검증", title, story: title, paymentVerified: "true", published })) f.set(key, value);
    if (revision) f.set("revision", revision);
    else f.set("photo", new Blob([new Uint8Array(photo)], { type: "image/jpeg" }), "test.jpg");
    return f;
  }
  try {
    const login = await send("/api/admin/session", "POST", JSON.stringify({ password: process.env.ADMIN_PASSWORD }));
    assert.equal(login.status, 200); cookie = login.headers.get("set-cookie")!.split(";")[0];
    const titles = ["주소검증 첫 이야기", "주소검증 둘째 이야기", "주소검증 셋째 이야기"];
    const created = await Promise.all(titles.map(title => send("/api/admin/stories", "POST", form(title))));
    for (const response of created) {
      assert.equal(response.status, 201);
      ids.push((await response.json()).id);
    }
    assert.equal(new Set(ids).size, 3);
    for (const [index, id] of ids.entries()) {
      const page = await fetch(`${base}/stories/${id}`).then(r => r.text());
      assert.ok(page.includes(titles[index]));
      for (const title of titles.filter(t => t !== titles[index])) assert.equal(page.includes(title), false);
    }
    const listing = await fetch(base + "/stories").then(r => r.text());
    for (const id of ids) assert.ok(listing.includes(`/stories/${id}`));
    assert.equal((await send(`/api/admin/stories/${ids[0]}`, "PUT", form("주소검증 수정된 이야기", "1"))).status, 200);
    const updated = await fetch(`${base}/stories/${ids[0]}`).then(r => r.text());
    assert.ok(updated.includes("주소검증 수정된 이야기"));
    assert.equal((await send(`/api/admin/stories/${ids[0]}`, "PUT", form("주소검증 비공개 이야기", "2", "false"))).status, 200);
    assert.equal((await fetch(`${base}/stories/${ids[0]}`).then(r => r.text())).includes("주소검증 비공개 이야기"), false);
    assert.equal((await fetch(`${base}/api/stories/${ids[0]}/photo`)).status, 404);
    assert.equal((await send(`/api/admin/stories/${ids[1]}`, "DELETE", JSON.stringify({ revision: 1 }))).status, 200);
    assert.equal((await fetch(`${base}/stories/${ids[1]}`).then(r => r.text())).includes(titles[1]), false);
    assert.ok((await fetch(`${base}/stories/${ids[2]}`).then(r => r.text())).includes(titles[2]));
    assert.equal((await fetch(`${base}/api/stories/${randomUUID()}/photo`)).status, 404);
    assert.equal((await pool.query("SELECT count(*)::int AS count FROM mat_stories WHERE id=ANY($1)", [ids])).rows[0].count, 2);
  } finally {
    await pool.query("DELETE FROM mat_stories WHERE id=ANY($1)", [ids]);
    await pool.end();
  }
});

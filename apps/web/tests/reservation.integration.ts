import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import sharp from "sharp";
import { database } from "../src/lib/db";
const base = process.env.TEST_BASE_URL || "http://127.0.0.1:4314";
if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
const pool = database();
test("private reservations are idempotent, admin-reviewed and never expose contact details", async () => {
  const id = randomUUID(); let storyId = ""; let cookie = "";
  const photo = await sharp({ create: { width: 400, height: 300, channels: 3, background: "#eee5cb" } }).jpeg().toBuffer();
  function form(amount = "7200") {
    const f = new FormData();
    for (const [key,value] of Object.entries({ id, displayName: "검증용 예약자", phone: "010-0000-9923", reason: "other", reasonOther: "통합 검증", title: "검증용 예약 제목", story: "가".repeat(333) + "a", paymentMethod: "easy", amount })) f.set(key,value);
    f.set("photo", new Blob([new Uint8Array(photo)], { type: "image/jpeg" }), "test.jpg"); return f;
  }
  const send = (path: string, method: string, body?: BodyInit, auth = false) => fetch(base+path, { method, headers: { origin: base, ...(auth ? { cookie } : {}) }, body });
  try {
    const oversized = form(); oversized.set("story", "가".repeat(333) + "ab");
    assert.equal((await send("/api/reservations", "POST", oversized)).status, 400);
    const requests = await Promise.all([send("/api/reservations", "POST", form()), send("/api/reservations", "POST", form())]);
    for (const r of requests) assert.equal(r.status,201);
    assert.equal((await pool.query("SELECT count(*)::int AS count FROM mat_reservations WHERE id=$1",[id])).rows[0].count,1);
    assert.equal((await send("/api/reservations","POST",form("7300"))).status,409);
    assert.equal((await fetch(base+`/api/admin/reservations/${id}/photo`)).status,401);
    assert.equal((await send(`/api/admin/reservations/${id}`,"DELETE")).status,401);
    assert.equal((await fetch(base+"/admin").then(r=>r.text())).includes("01000009923"),false);
    assert.equal((await fetch(base+"/").then(r=>r.text())).includes("검증용 예약 제목"),false);
    const login = await send("/api/admin/session","POST",JSON.stringify({password:process.env.ADMIN_PASSWORD}));
    assert.equal(login.status,200);cookie=login.headers.get("set-cookie")!.split(";")[0];
    assert.equal((await send(`/api/admin/reservations/${id}/photo`,"GET",undefined,true)).status,200);
    const admin = await send("/admin","GET",undefined,true).then(r=>r.text());assert.ok(admin.includes("01000009923"));
    const promote = () => {const f=new FormData();for(const[k,v]of Object.entries({reservationId:id,matNumber:"9903",matSize:"large",displayName:"검증용 예약자",title:"검증용 예약 제목",story:"가".repeat(333)+"a",paymentVerified:"true",published:"true"}))f.set(k,v);return f;};
    const created = await send("/api/admin/stories","POST",promote(),true);assert.equal(created.status,201);storyId=(await created.json()).id;
    assert.equal((await send("/api/admin/stories","POST",promote(),true)).status,409);
    const publicPage = await fetch(base+`/stories/${storyId}`).then(r=>r.text());
    assert.ok(publicPage.includes("검증용 예약 제목"));assert.equal(publicPage.includes("01000009923"),false);
    const deviceId=randomUUID();
    const votes=await Promise.all(["like","empathy","sad","cheer","like","cheer"].map(kind=>send(`/api/stories/${storyId}/reaction`,"POST",JSON.stringify({deviceId,action:"react",kind}))));
    for(const r of votes)assert.equal(r.status,200);
    const status=await send(`/api/stories/${storyId}/reaction`,"POST",JSON.stringify({deviceId,action:"status"})).then(r=>r.json());
    assert.deepEqual(status.counts,{like:1,empathy:1,sad:1,cheer:1});assert.equal(status.selected.length,4);
    assert.equal((await send(`/api/admin/reservations/${id}`,"DELETE",undefined,true)).status,200);
    assert.equal((await send(`/api/admin/reservations/${id}/photo`,"GET",undefined,true)).status,404);
    assert.equal((await fetch(base+`/api/stories/${storyId}/photo`)).status,200);
    await send("/api/admin/session","DELETE",undefined,true);
  } finally {
    await pool.query("DELETE FROM mat_reservations WHERE id=$1",[id]);
    if(storyId)await pool.query("DELETE FROM mat_stories WHERE id=$1",[storyId]);
    await pool.end();
  }
});

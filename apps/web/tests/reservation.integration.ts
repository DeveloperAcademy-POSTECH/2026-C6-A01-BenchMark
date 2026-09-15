import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import sharp from "sharp";
import { database } from "../src/lib/db";
const base = process.env.TEST_BASE_URL || "http://127.0.0.1:4314";
if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
const pool = database();
test("private reservations are idempotent, admin-reviewed and never expose contact details", async () => {
  const id = randomUUID(); const secondId = randomUUID(); const legacyId = randomUUID(); let storyId = ""; let cookie = "";
  const photo = await sharp({ create: { width: 400, height: 300, channels: 3, background: "#eee5cb" } }).jpeg().toBuffer();
  function form(amount = "10000") {
    const f = new FormData();
    for (const [key,value] of Object.entries({ id, email: "donor@example.test", displayName: "검증용 예약자", reason: "other", reasonOther: "통합 검증", title: "검증용 예약 제목", story: "가".repeat(333) + "a", paymentMethod: "easy", amount })) f.set(key,value);
    f.set("photo", new Blob([new Uint8Array(photo)], { type: "image/jpeg" }), "test.jpg"); return f;
  }
  const send = (path: string, method: string, body?: BodyInit, auth = false) => fetch(base+path, { method, headers: { origin: base, "x-forwarded-for": "192.0.2.26", ...(auth ? { cookie } : {}) }, body });
  try {
    for (const email of ["", "invalid"]) {
      const invalid = form(); invalid.set("email", email);
      assert.equal((await send("/api/reservations", "POST", invalid)).status, 400);
    }
    const oversized = form(); oversized.set("story", "가".repeat(333) + "ab");
    assert.equal((await send("/api/reservations", "POST", oversized)).status, 400);
    const requests = await Promise.all([send("/api/reservations", "POST", form()), send("/api/reservations", "POST", form())]);
    for (const r of requests) assert.equal(r.status,201);
    assert.equal((await pool.query("SELECT count(*)::int AS count FROM mat_reservations WHERE id=$1",[id])).rows[0].count,1);
    assert.equal((await send("/api/reservations","POST",form("25000"))).status,409);
    for (const amount of ["", "9999"]) assert.equal((await send("/api/reservations", "POST", form(amount))).status, 400);
    const changedEmail = form(); changedEmail.set("email", "changed@example.test");
    assert.equal((await send("/api/reservations", "POST", changedEmail)).status, 409);
    const second = form("25000"); second.set("id", secondId);
    second.set("phone", "010-0000-9923");
    second.set("paymentMethod", "other");
    assert.equal((await send("/api/reservations", "POST", second)).status, 201);
    assert.deepEqual((await pool.query("SELECT phone,email FROM mat_reservations WHERE id=ANY($1::uuid[])", [[id, secondId]])).rows, [{ phone: null, email: "donor@example.test" }, { phone: null, email: "donor@example.test" }]);
    assert.equal((await pool.query("SELECT payment_method FROM mat_reservations WHERE id=$1", [secondId])).rows[0].payment_method, "other");
    assert.deepEqual((await pool.query("SELECT amount FROM mat_reservations WHERE id=ANY($1::uuid[]) ORDER BY amount", [[id, secondId]])).rows.map(r => r.amount), [10000,25000]);
    await pool.query("INSERT INTO mat_reservations(id,display_name,phone,reason,reason_other,title,story,photo,payment_method,amount) SELECT $1,display_name,'01000009923',reason,reason_other,title,story,photo,payment_method,7200 FROM mat_reservations WHERE id=$2", [legacyId,id]);
    assert.equal((await fetch(base+`/api/admin/reservations/${id}/photo`)).status,401);
    assert.equal((await send(`/api/admin/reservations/${id}`,"DELETE")).status,401);
    assert.equal((await fetch(base+"/admin").then(r=>r.text())).includes("01000009923"),false);
    assert.equal((await fetch(base+"/").then(r=>r.text())).includes("검증용 예약 제목"),false);
    const login = await send("/api/admin/session","POST",JSON.stringify({password:process.env.ADMIN_PASSWORD}));
    assert.equal(login.status,200);cookie=login.headers.get("set-cookie")!.split(";")[0];
    assert.equal((await send(`/api/admin/reservations/${id}/photo`,"GET",undefined,true)).status,200);
    const admin = await send("/admin","GET",undefined,true).then(r=>r.text());assert.ok(admin.includes("donor@example.test")); assert.ok(admin.includes("01000009923")); assert.ok(admin.includes("7,200")); assert.ok(admin.includes("10,000")); assert.ok(admin.includes("25,000"));
    const promote = () => {const f=new FormData();for(const[k,v]of Object.entries({reservationId:id,matNumber:"9903",matSize:"large",displayName:"검증용 예약자",title:"검증용 예약 제목",story:"가".repeat(333)+"a",paymentVerified:"true",published:"true"}))f.set(k,v);return f;};
    const created = await send("/api/admin/stories","POST",promote(),true);assert.equal(created.status,201);storyId=(await created.json()).id;
    assert.equal((await send("/api/admin/stories","POST",promote(),true)).status,409);
    const publicPage = await fetch(base+`/stories/${storyId}`).then(r=>r.text());
    assert.ok(publicPage.includes("검증용 예약 제목"));assert.equal(publicPage.includes("01000009923"),false);assert.equal(publicPage.includes("donor@example.test"),false);
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
    await pool.query("DELETE FROM mat_reservations WHERE id=ANY($1::uuid[])",[[id,secondId,legacyId]]);
    if(storyId)await pool.query("DELETE FROM mat_stories WHERE id=$1",[storyId]);
    await pool.end();
  }
});

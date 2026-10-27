import {test} from "node:test";
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {database} from "../src/lib/db";
import {allowedCampusPosition} from "../src/lib/campus";
const base=process.env.TEST_BASE_URL||"http://127.0.0.1:4314";
if(!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test"))throw new Error("Use isolated benchmark_mat_test only.");
const db=database(),writers:string[]=[];let cookie="";
async function send(path:string,method="GET",body?:unknown,token?:string,admin=false,origin=base) {
  return fetch(base+path,{method,headers:{"content-type":"application/json",origin,...(token?{authorization:`Bearer ${token}`} : {}),...(admin?{cookie}:{})},body:body===undefined?undefined:JSON.stringify(body),redirect:"manual"});
}
async function json(response:Response,status=200){assert.equal(response.status,status,await response.clone().text());return response.json();}
async function grant(){const g=await json(await send("/api/admin/campus/grants","POST",{reviewConfirmed:true},undefined,true),201);writers.push(g.id);return g;}
async function publish(id:string,revision:number,status="published") {return send(`/api/admin/campus/ois/${id}`,"PUT",{status,revision},undefined,true);}
async function publicList(){return json(await send("/api/campus/ois"));}
test("campus shared API enforces grants, ownership, review, same coordinates across clients and revocation",async()=>{
 try {
  await json(await send("/api/admin/campus/grants"),401);
  const login=await send("/api/admin/session","POST",{password:process.env.ADMIN_PASSWORD});await json(login);cookie=login.headers.get("set-cookie")!.split(";")[0];
  await json(await send("/api/admin/campus/grants","POST",{reviewConfirmed:true},undefined,true,"https://bad.invalid"),403);
  await json(await send("/api/admin/campus/grants","POST",{reviewConfirmed:false},undefined,true),400);
  const g=await grant();
  const redemption=await Promise.all([send("/api/campus/session","POST",{code:g.code}),send("/api/campus/session","POST",{code:g.code})]);
  assert.deepEqual(redemption.map(r=>r.status).sort(),[200,401]);
  const auth=await json(redemption.find(r=>r.status===200)!);
  const other=await grant(),otherAuth=await json(await send("/api/campus/session","POST",{code:other.code}));
  let coordinate:[number,number]|undefined;
  for(let lat=36.005;lat<=36.02&&!coordinate;lat+=.0005)for(let lon=129.32;lon<=129.34;lon+=.0005)if(allowedCampusPosition(lat,lon)){coordinate=[lat,lon];break;}
  assert.ok(coordinate);
  const p={id:randomUUID(),campusID:"postech",model:"helmet-oi",latitude:coordinate[0],longitude:coordinate[1],heightMeters:1.2,headingDegrees:45,displayName:"가상 검증 농부",title:"캠퍼스 전체 공유 테스트",story:"운영 데이터가 아닌 테스트 이야기"};
  const endpoint=`/api/campus/ois/${p.id}`;
  await json(await send("/api/campus/ois","POST",p),401);
  await json(await send("/api/campus/ois","POST",{...p,status:"published"},auth.token),400);
  await json(await send("/api/campus/ois","POST",{...p,latitude:37.5},auth.token),400);
  await json(await send("/api/campus/ois","POST",p,auth.token),201);
  await json(await send("/api/campus/ois","POST",p,auth.token)); // retry does not duplicate
  await json(await send("/api/campus/ois","POST",{...p,story:"다른 내용"},auth.token),409);
  await json(await send(endpoint),404);await json(await send(endpoint,"GET",undefined,otherAuth.token),404);
  assert.equal((await publicList()).items.some((o:{id:string})=>o.id===p.id),false);
  assert.equal((await json(await send("/api/campus/mine","GET",undefined,auth.token))).items.length,1);
  await json(await send(endpoint,"PUT",{...p,revision:1},otherAuth.token),409);
  await json(await publish(p.id,1));
  assert.equal((await json(await send("/api/campus/ois","POST",p,auth.token))).status,"published");
  const a=await json(await send(endpoint)),b=await json(await send(endpoint));
  assert.deepEqual(a,b);assert.equal(a.latitude,p.latitude);assert.equal(a.longitude,p.longitude);assert.equal(a.storyID,p.id);assert.equal(a.story,p.story);
  assert.equal("writerID" in a,false);assert.equal("token_hash" in a,false);
  assert.ok((await send(endpoint)).headers.get("cache-control")?.includes("no-store"));
  await json(await send(endpoint,"PUT",{...p,revision:1},auth.token),409);
  await json(await send(endpoint,"PUT",{...p,story:"수정된 이야기",revision:2},auth.token));
  await json(await send(endpoint),404);
  await json(await publish(p.id,3));
  // Two concurrent updates cannot silently overwrite one another.
  const races=await Promise.all([send(endpoint,"PUT",{...p,revision:4},auth.token),send(endpoint,"PUT",{...p,title:"동시 수정",revision:4},auth.token)]);
  assert.deepEqual(races.map(r=>r.status).sort(),[200,409]);
  await json(await publish(p.id,5));
  const reissue=await json(await send("/api/admin/campus/grants","POST",{reviewConfirmed:true,writerID:g.id},undefined,true),201);
  await json(await send("/api/campus/mine","GET",undefined,auth.token),401);
  const renewed=await json(await send("/api/campus/session","POST",{code:reissue.code}));assert.equal(renewed.writerID,auth.writerID);
  assert.equal((await json(await send("/api/campus/mine","GET",undefined,renewed.token))).items[0].id,p.id);
  await json(await send(`/api/admin/campus/grants/${g.id}`,"DELETE",undefined,undefined,true));
  await json(await send(endpoint),404);await json(await send("/api/campus/ois","POST",{...p,id:randomUUID()},renewed.token),401);
  assert.equal((await publicList()).items.some((o:{id:string})=>o.id===p.id),false);
  await json(await publish(p.id,6),409);
  const deleted={...p,id:randomUUID()};await json(await send("/api/campus/ois","POST",deleted,otherAuth.token),201);
  await json(await send(`/api/campus/ois/${deleted.id}`,"DELETE",{revision:2},otherAuth.token),409);
  await json(await send(`/api/campus/ois/${deleted.id}`,"DELETE",{revision:1},otherAuth.token));
  await json(await send(`/api/campus/ois/${deleted.id}`,"GET",undefined,otherAuth.token),404);
  const expired=await grant();await db.query("UPDATE campus_writers SET code_expires_at=now()-interval '1 second' WHERE id=$1",[expired.id]);
  await json(await send("/api/campus/session","POST",{code:expired.code}),401);
  await db.query("UPDATE campus_writers SET token_expires_at=now()-interval '1 second' WHERE id=$1",[other.id]);
  await json(await send("/api/campus/mine","GET",undefined,otherAuth.token),401);
  await json(await send("/api/campus/ois?cursor=invalid"),400);
  await json(await send("/api/campus/ois?south=1"),400);
  await json(await send("/api/campus/session","POST",null),400);
  // Pagination must include every published record, with deterministic UUID cursors.
  await db.query(`INSERT INTO campus_ois(id,writer_id,campus_id,model,latitude,longitude,height_meters,heading_degrees,display_name,title,story,status,request_hash)
    SELECT gen_random_uuid(),$1,'postech','helmet-oi',$2,$3,1,0,'검증','페이지','가상 자료','published','test' FROM generate_series(1,205)`,[other.id,p.latitude,p.longitude]);
  const first=await publicList();assert.equal(first.items.length,200);assert.ok(first.nextCursor);
  const second=await json(await send("/api/campus/ois?cursor="+first.nextCursor));assert.equal(second.items.length,5);assert.equal(second.nextCursor,null);
  assert.equal(new Set([...first.items,...second.items].map(o=>o.id)).size,205);
  assert.ok((await db.query("SELECT count(*)::int n FROM campus_reviews WHERE oi_id=$1",[p.id])).rows[0].n>=3);
 } finally {
  for(const id of writers){await db.query("DELETE FROM campus_reviews WHERE oi_id IN (SELECT id FROM campus_ois WHERE writer_id=$1)",[id]);await db.query("DELETE FROM campus_ois WHERE writer_id=$1",[id]);await db.query("DELETE FROM campus_writers WHERE id=$1",[id]);}
  await db.end();
 }
});

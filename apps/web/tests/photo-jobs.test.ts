import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Miniflare } from "miniflare";
import { runWithStorageBindings } from "../lib/sites-storage";
import { servePhotoSource, sourceSignature, processPhoto } from "../lib/photo-jobs";

test("photo source authenticates and permits exactly one cross-instance claim", {timeout:60000}, async()=> {
  const mf=new Miniflare({modules:true,script:"export default {fetch(){return new Response('test')}}",compatibilityDate:"2026-05-15",d1Databases:["DB"],r2Buckets:["BUCKET"]});
  const previous=process.env.SESSION_WRAP_KEY;
  process.env.SESSION_WRAP_KEY="test-only-key-for-photo-source-1234567890";
  try {
    const db=await mf.getD1Database("DB");const bucket=await mf.getR2Bucket("BUCKET");
    await db.prepare("CREATE TABLE photo_jobs(id TEXT PRIMARY KEY,object_key TEXT NOT NULL,expires_at INTEGER NOT NULL,consumed INTEGER NOT NULL)").run();
    await runWithStorageBindings({DB:db as unknown as D1Database,BUCKET:bucket as unknown as R2Bucket},async()=> {
      const id=randomUUID();const key=`photo-jobs/${id}`;const bytes=Buffer.from("private-test-original");
      await bucket.put(key,bytes);
      await db.prepare("INSERT INTO photo_jobs VALUES(?,?,?,0)").bind(id,key,Date.now()+120000).run();
      const timestamp=String(Math.floor(Date.now()/1000));
      const request=()=>new Request(`https://test.local/${id}`,{headers:{"x-photo-id":id,"x-photo-timestamp":timestamp,"x-photo-signature":sourceSignature(timestamp,id)}});
      await assert.rejects(()=>servePhotoSource(new Request(`https://test.local/${id}`),id),{status:401});
      const results=await Promise.allSettled(Array.from({length:12},()=>servePhotoSource(request(),id)));
      const winners=results.filter(r=>r.status==="fulfilled");assert.equal(winners.length,1);
      const response=(winners[0] as PromiseFulfilledResult<Response>).value;
      assert.deepEqual(Buffer.from(await response.arrayBuffer()),bytes);
      assert.equal(response.headers.get("cache-control"),"no-store");
      assert.ok(results.filter(r=>r.status==="rejected").every(r=>(r as PromiseRejectedResult).reason.status===410));
      const expired=randomUUID();
      await db.prepare("INSERT INTO photo_jobs VALUES(?,?,?,0)").bind(expired,key,Date.now()-1).run();
      await assert.rejects(()=>servePhotoSource(new Request(`https://test.local/${expired}`,{headers:{"x-photo-id":expired,"x-photo-timestamp":timestamp,"x-photo-signature":sourceSignature(timestamp,expired)}}),expired),{status:410});
    });
  } finally { if(previous===undefined)delete process.env.SESSION_WRAP_KEY;else process.env.SESSION_WRAP_KEY=previous;await mf.dispose(); }
});

test("processor failure removes private input and job record", {timeout:60000},async()=> {
  const mf=new Miniflare({modules:true,script:"export default {fetch(){return new Response('test')}}",compatibilityDate:"2026-05-15",d1Databases:["DB"],r2Buckets:["BUCKET"]});
  const previousKey=process.env.SESSION_WRAP_KEY;const previousUrl=process.env.PHOTO_PROCESSOR_URL;const previousFetch=globalThis.fetch;
  process.env.SESSION_WRAP_KEY="test-only-key-for-photo-source-1234567890";process.env.PHOTO_PROCESSOR_URL="https://test-photo.netlify.app/.netlify/functions/photo";
  try {
    const db=await mf.getD1Database("DB");const bucket=await mf.getR2Bucket("BUCKET");
    await db.prepare("CREATE TABLE photo_jobs(id TEXT PRIMARY KEY,object_key TEXT NOT NULL,expires_at INTEGER NOT NULL,consumed INTEGER NOT NULL)").run();
    await runWithStorageBindings({DB:db as unknown as D1Database,BUCKET:bucket as unknown as R2Bucket},async()=> {
      globalThis.fetch=async(_input,options)=> {
        assert.equal(options?.redirect,"manual");assert.equal(options?.cache,"no-store");
        return new Response(null,{status:302,headers:{Location:"https://unexpected.example.test"}});
      };
      await assert.rejects(()=>processPhoto(Buffer.from("test input")),{status:503});
      globalThis.fetch=previousFetch;
      assert.equal((await db.prepare("SELECT count(*) AS n FROM photo_jobs").first<{n:number}>())?.n,0);
      assert.equal((await bucket.list({prefix:"photo-jobs/"})).objects.length,0);
    });
  } finally {
    globalThis.fetch=previousFetch;
    if(previousKey===undefined)delete process.env.SESSION_WRAP_KEY;else process.env.SESSION_WRAP_KEY=previousKey;
    if(previousUrl===undefined)delete process.env.PHOTO_PROCESSOR_URL;else process.env.PHOTO_PROCESSOR_URL=previousUrl;
    await mf.dispose();
  }
});

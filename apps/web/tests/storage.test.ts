import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { Miniflare } from "miniflare";
import { database, prepareQuery } from "../lib/db";
import { runWithStorageBindings, storePhoto, loadPhoto } from "../lib/sites-storage";
import { rateLimit } from "../lib/security";

test("D1 and private R2 preserve constraints, atomic retries and photo bytes", { timeout: 60000 }, async () => {
  const mf = new Miniflare({ modules:true, script:"export default { fetch(){ return new Response('test'); } }", compatibilityDate:"2026-05-15", d1Databases:["DB"],r2Buckets:["BUCKET"] });
  try {
    const db = await mf.getD1Database("DB");
    const bucket = await mf.getR2Bucket("BUCKET");
    const directory = new URL("../drizzle/",import.meta.url);
    const files = (await readdir(directory)).filter(file=>file.endsWith(".sql")).sort();
    const migration = (await Promise.all(files.map(file=>readFile(new URL(file,directory),"utf8")))).join("--> statement-breakpoint");
    for (const sql of migration.split("--> statement-breakpoint")) if(sql.trim()) await db.prepare(sql).run();
    await runWithStorageBindings({DB:db as unknown as D1Database,BUCKET:bucket as unknown as R2Bucket},async()=> {
      const storage = database();
      const id = randomUUID();
      const bytes = Buffer.from("test-only-image-bytes");
      const photo = await storePhoto(bytes);
      assert.deepEqual(await loadPhoto(photo),bytes);
      const insert = "INSERT INTO mat_stories(id,mat_number,mat_size,display_name,story,photo,payment_verified,published) VALUES($1,1,'small','Test','Story',$2,$3,$4)";
      await assert.rejects(()=>storage.query(insert,[id,photo,false,true]),/CHECK constraint/);
      await storage.query(insert,[id,photo,true,true]);
      const sameMat = randomUUID();
      await storage.query(insert,[sameMat,photo,true,true]);
      assert.equal((await storage.query("SELECT id FROM mat_stories WHERE mat_number=1")).rowCount,2);
      await Promise.all(Array.from({length:10},()=>storage.query("INSERT INTO mat_reactions(story_id,device_hash,kind) VALUES($1,'test','empathy') ON CONFLICT DO NOTHING",[id])));
      assert.equal((await storage.query<{count:number}>("SELECT count(*) AS count FROM mat_reactions WHERE story_id=$1",[id])).rows[0].count,1);
      await storage.query("DELETE FROM mat_reactions WHERE story_id=$1 AND device_hash='test'",[id]);
      assert.equal((await storage.query("SELECT * FROM mat_reactions")).rowCount,0);
      await assert.rejects(()=>storage.batch([
        {sql:"UPDATE mat_stories SET title='Must roll back' WHERE id=$1",values:[id]},
        {sql:"UPDATE mat_stories SET published=1,payment_verified=0 WHERE id=$1",values:[id]},
      ]),/CHECK constraint/);
      assert.equal((await storage.query<{title:string}>("SELECT title FROM mat_stories WHERE id=$1",[id])).rows[0].title,"");
      const outcomes = await Promise.all(Array.from({length:5},()=>storage.query("UPDATE mat_stories SET title='Winner',revision=revision+1 WHERE id=$1 AND revision=1 RETURNING id",[id])));
      assert.equal(outcomes.filter(r=>r.rowCount).length,1);
      const limits = await Promise.allSettled(Array.from({length:11},()=>rateLimit("test",10,900)));
      assert.equal(limits.filter(r=>r.status==="fulfilled").length,10);
      await storage.query("INSERT INTO mat_reactions(story_id,device_hash,kind) VALUES($1,'test','like')",[id]);
      await storage.query("DELETE FROM mat_stories WHERE id=$1",[id]);
      assert.equal((await storage.query("SELECT * FROM mat_reactions")).rowCount,0);
      await bucket.delete(photo);
      await assert.rejects(()=>loadPhoto(photo),/missing/);
    });
  } finally { await mf.dispose(); }
});

test("repeated SQL parameters preserve order and missing inputs fail closed",()=> {
  const prepared = prepareQuery({sql:"SELECT $2,$1::uuid,$2",values:["id",7]});
  assert.deepEqual(prepared,{sql:"SELECT ?,?,?",values:[7,"id",7]});
  assert.throws(()=>prepareQuery({sql:"SELECT $2",values:["id"]}),/Missing SQL parameter/);
});

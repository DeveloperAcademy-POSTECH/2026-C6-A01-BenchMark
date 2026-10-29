import {test} from "node:test";
import assert from "node:assert/strict";
import {readdir,readFile} from "node:fs/promises";
import {randomUUID} from "node:crypto";
import {Miniflare} from "miniflare";

test("validation migration preserves populated relationships and blocks invalid direct writes",{timeout:60000},async()=> {
  const mf=new Miniflare({modules:true,script:"export default {fetch(){return new Response('test')}}",compatibilityDate:"2026-05-15",d1Databases:["DB"]});
  try {
    const db=await mf.getD1Database("DB");
    const directory=new URL("../drizzle/",import.meta.url);
    const files=(await readdir(directory)).filter(file=>file.endsWith(".sql")).sort();
    async function apply(file:string) {
      for(const sql of (await readFile(new URL(file,directory),"utf8")).split("--> statement-breakpoint"))if(sql.trim())await db.prepare(sql).run();
    }
    for(const file of files.filter(file=>file<'0003'))await apply(file);
    const story=randomUUID();const reservation=randomUUID();
    await db.prepare("INSERT INTO mat_stories(id,mat_number,mat_size,display_name,story,photo) VALUES(?,1,'small','Test','Story','test-photo')").bind(story).run();
    await db.prepare("INSERT INTO mat_reactions(story_id,device_hash,kind) VALUES(?,'test-device','like')").bind(story).run();
    await db.prepare("INSERT INTO mat_reservations(id,display_name,reason,title,story,photo,payment_method,amount,source_story_id,story_id) VALUES(?,'Test','story','Title','Story','test-photo','deposit',10000,?,?)").bind(reservation,story,story).run();
    const query="SELECT id,display_name,phone,email,reason,reason_other,title,story,photo,payment_method,amount,source_story_id,story_id,created_at FROM mat_reservations";
    const before=await db.prepare(query).all();
    for(const file of files.filter(file=>file>='0003'))await apply(file);
    assert.deepEqual((await db.prepare(query).all()).results,before.results);
    assert.equal((await db.prepare("SELECT count(*) AS n FROM mat_reactions").first<{n:number}>())?.n,1);
    await assert.rejects(()=>db.prepare("UPDATE mat_stories SET display_name='' WHERE id=?").bind(story).run(),/CHECK constraint/);
    await assert.rejects(()=>db.prepare("UPDATE mat_reservations SET title='' WHERE id=?").bind(reservation).run(),/CHECK constraint/);
    await assert.rejects(()=>db.prepare("UPDATE mat_reservations SET phone='invalid' WHERE id=?").bind(reservation).run(),/CHECK constraint/);
  } finally {await mf.dispose();}
});

import { createHash } from "node:crypto";
import { database } from "@/lib/db";
import { bindings } from "@/lib/sites-storage";
import { migrationTable, migrationTables, requireMigration } from "@/lib/migration";
import { boundedBody, HttpError, jsonError } from "@/lib/security";

export const dynamic = "force-dynamic";
export async function POST(request: Request) {
  try {
    requireMigration(request);
    const url = new URL(request.url);
    const table = migrationTable(url.searchParams.get("table"));
    if (url.searchParams.get("photo") === "1") {
      if (!["mat_stories","mat_reservations"].includes(table)) throw new HttpError(400,"Invalid photo table");
      const id = url.searchParams.get("id");
      if (!id || !/^[0-9a-f-]{36}$/.test(id)) throw new HttpError(400,"Invalid photo ID");
      const bytes = await boundedBody(request,5*1024*1024);
      if (!bytes.length) throw new HttpError(400,"Empty photo");
      const sha256 = createHash("sha256").update(bytes).digest("hex");
      const key = `photos/import/${table}/${id}/${sha256}.jpg`;
      await bindings().bucket.put(key,bytes,{httpMetadata:{contentType:"image/jpeg"},customMetadata:{sha256}});
      return Response.json({key,sha256},{headers:{"Cache-Control":"private, no-store"}});
    }
    const rows: unknown = JSON.parse((await boundedBody(request,1024*1024)).toString());
    if (!Array.isArray(rows) || !rows.length || rows.length > 100) throw new HttpError(400,"Invalid migration batch");
    const columns = migrationTables[table];
    const queries = rows.map(row => {
      if (!row || typeof row !== "object" || columns.some(column=>!(column in row))) throw new HttpError(400,"Incomplete migration row");
      const values = columns.map(column=>row[column]);
      return {sql:`INSERT INTO ${table}(${columns.join(",")}) VALUES(${columns.map((_,i)=>`$${i+1}`).join(",")}) ON CONFLICT DO UPDATE SET ${columns.map(column=>`${column}=excluded.${column}`).join(",")}`,values};
    });
    await database().batch(queries);
    return Response.json({imported:rows.length},{headers:{"Cache-Control":"private, no-store"}});
  } catch (error) { return jsonError(error); }
}
export async function GET(request: Request) {
  try {
    requireMigration(request);
    const table = migrationTable(new URL(request.url).searchParams.get("table"));
    const result = await bindings().db.prepare(`SELECT ${migrationTables[table].join(",")} FROM ${table}`).all<Record<string,unknown>>();
    const rows = await Promise.all(result.results.map(async row=> {
      for(const field of ["payment_verified","published"]) if(field in row) row[field]=!!row[field];
      if(typeof row.properties === "string") row.properties=JSON.parse(row.properties);
      if (typeof row.photo !== "string") return row;
      const photo = await bindings().bucket.get(row.photo);
      if (!photo) throw new Error("Migration photo is missing");
      return {...row,photo:createHash("sha256").update(Buffer.from(await photo.arrayBuffer())).digest("hex")};
    }));
    return Response.json(rows,{headers:{"Cache-Control":"private, no-store"}});
  } catch(error) { return jsonError(error); }
}

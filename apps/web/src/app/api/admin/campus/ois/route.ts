import { fields, reply, uuid } from "@/lib/campus";
import { database } from "@/lib/db";
import { HttpError, jsonError, requireAdmin } from "@/lib/security";
export const dynamic="force-dynamic";
export async function GET(request:Request) {
  try {await requireAdmin();const cursor=new URL(request.url).searchParams.get("cursor");
    if(cursor&&!uuid.safeParse(cursor).success)throw new HttpError(400,"조회 기준을 확인해주세요.");
    const result=await database().query(`SELECT ${fields},o.writer_id AS "writerID",w.revoked_at AS "writerRevokedAt" FROM campus_ois o JOIN campus_writers w ON w.id=o.writer_id WHERE ($1::uuid IS NULL OR o.id>$1) ORDER BY o.id LIMIT 201`,[cursor]);
    const items=result.rows.slice(0,200);return reply({items,nextCursor:result.rows.length>200?items.at(-1).id:null});
  }catch(error){return jsonError(error);}
}

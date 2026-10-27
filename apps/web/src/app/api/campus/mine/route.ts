import { fields, reply, uuid, writer } from "@/lib/campus";
import { database } from "@/lib/db";
import { HttpError, jsonError } from "@/lib/security";
export const dynamic="force-dynamic";
export async function GET(request:Request) {
  try {
    const owner=await writer(request),cursor=new URL(request.url).searchParams.get("cursor");
    if(cursor&&!uuid.safeParse(cursor).success)throw new HttpError(400,"조회 기준을 확인해주세요.");
    const result=await database().query(`SELECT ${fields} FROM campus_ois o WHERE writer_id=$1 AND ($2::uuid IS NULL OR o.id>$2) ORDER BY o.id LIMIT 201`,[owner,cursor]);
    const items=result.rows.slice(0,200);return reply({items,nextCursor:result.rows.length>200?items.at(-1).id:null});
  }catch(error){return jsonError(error);}
}

import { jsonBody, reply, uuid } from "@/lib/campus";
import { database } from "@/lib/db";
import { checkOrigin, HttpError, jsonError, requireAdmin } from "@/lib/security";
export async function PUT(request:Request,context:{params:Promise<{id:string}>}) {
  let client;
  try {
    checkOrigin(request);await requireAdmin();const id=(await context.params).id,input=await jsonBody(request,2048);
    if(!["published","hidden"].includes(input.status)||!Number.isSafeInteger(input.revision)||input.revision<1)throw new HttpError(400,"공개 상태와 버전을 확인해주세요.");
    if(!uuid.safeParse(id).success)throw new HttpError(400,"ID를 확인해주세요.");
    client=await database().connect();await client.query("BEGIN");
    const result=await client.query(`UPDATE campus_ois o SET status=$1,revision=revision+1,updated_at=now()
      WHERE id=$2 AND revision=$3 AND EXISTS(SELECT 1 FROM campus_writers w WHERE w.id=o.writer_id AND w.revoked_at IS NULL) RETURNING revision`,[input.status,id,input.revision]);
    if(!result.rowCount)throw new HttpError(409,"권한이 취소되었거나 내용이 바뀌었습니다. 새로고침 후 다시 검토해주세요.");
    await client.query("INSERT INTO campus_reviews(oi_id,action,revision) VALUES($1,$2,$3)",[id,input.status,result.rows[0].revision]);
    await client.query("COMMIT");return reply({ok:true});
  }catch(error){if(client)await client.query("ROLLBACK");return jsonError(error);}
  finally{client?.release();}
}

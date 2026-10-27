import { campusInput, digest, fields, inputValues, jsonBody, reply, uuid, writer } from "@/lib/campus";
import { database } from "@/lib/db";
import { HttpError, jsonError, rateLimit } from "@/lib/security";
type Context={params:Promise<{id:string}>};
export const dynamic="force-dynamic";
async function identifier(context:Context){const p=uuid.safeParse((await context.params).id);if(!p.success)throw new HttpError(404,"오이를 찾을 수 없습니다.");return p.data;}
export async function GET(request:Request,context:Context) {
  try {
    const id=await identifier(context);
    const owner=request.headers.has("authorization")?await writer(request):null;
    const result=await database().query(`SELECT ${fields} FROM campus_ois o JOIN campus_writers w ON w.id=o.writer_id
      WHERE o.id=$1 AND w.revoked_at IS NULL AND (o.status='published' OR o.writer_id=$2::uuid)`,[id,owner]);
    if(!result.rowCount) throw new HttpError(404,"공개되지 않았거나 삭제된 오이입니다.");
    return reply(result.rows[0]);
  }catch(error){return jsonError(error);}
}
export async function PUT(request:Request,context:Context) {
  try {
    const owner=await writer(request);await rateLimit(`campus:write:${owner}`,60,60);
    const id=await identifier(context),body=await jsonBody(request),{revision,...input}=body;
    if(!Number.isSafeInteger(revision)||revision<1) throw new HttpError(400,"수정 버전을 확인해주세요.");
    const parsed=campusInput.safeParse(input);
    if(!parsed.success||parsed.data.id!==id)throw new HttpError(400,"내용과 위치를 확인해주세요.");
    const p=parsed.data;
    const result=await database().query(`UPDATE campus_ois SET campus_id=$1,model=$2,latitude=$3,longitude=$4,height_meters=$5,
      heading_degrees=$6,display_name=$7,title=$8,story=$9,status='pending',revision=revision+1,request_hash=$10,updated_at=now()
      WHERE id=$11 AND writer_id=$12 AND revision=$13 RETURNING id`,[...inputValues(p),digest(JSON.stringify(p)),id,owner,revision]);
    if(!result.rowCount)throw new HttpError(409,"작성 권한이나 최신 버전을 확인해주세요.");
    return reply({id,status:"pending"});
  }catch(error){return jsonError(error);}
}
export async function DELETE(request:Request,context:Context) {
  try {
    const owner=await writer(request),id=await identifier(context),input=await jsonBody(request,2048);
    if(!Number.isSafeInteger(input.revision)||input.revision<1)throw new HttpError(400,"삭제 버전을 확인해주세요.");
    const result=await database().query("DELETE FROM campus_ois WHERE id=$1 AND writer_id=$2 AND revision=$3 RETURNING id",[id,owner,input.revision]);
    if(!result.rowCount)throw new HttpError(409,"작성 권한이나 최신 버전을 확인해주세요.");
    return reply({ok:true});
  }catch(error){return jsonError(error);}
}

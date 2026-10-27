import { reply, uuid } from "@/lib/campus";
import { database } from "@/lib/db";
import { checkOrigin, HttpError, jsonError, requireAdmin } from "@/lib/security";
export async function DELETE(request:Request,context:{params:Promise<{id:string}>}) {
  try {checkOrigin(request);await requireAdmin();const id=(await context.params).id;
    if(!uuid.safeParse(id).success)throw new HttpError(400,"ID를 확인해주세요.");
    const result=await database().query("UPDATE campus_writers SET revoked_at=now(),token_hash=NULL WHERE id=$1 RETURNING id",[id]);
    if(!result.rowCount)throw new HttpError(404,"작성 권한을 찾지 못했습니다.");return reply({ok:true});
  }catch(error){return jsonError(error);}
}

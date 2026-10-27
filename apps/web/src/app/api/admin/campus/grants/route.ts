import { jsonBody, newGrant, reply, uuid } from "@/lib/campus";
import { database } from "@/lib/db";
import { checkOrigin, HttpError, jsonError, requireAdmin } from "@/lib/security";
export const dynamic="force-dynamic";
export async function GET() {
  try {await requireAdmin();return reply({items:(await database().query("SELECT id,created_at,redeemed_at,revoked_at,code_expires_at,token_expires_at FROM campus_writers ORDER BY created_at DESC LIMIT 200")).rows});}
  catch(error){return jsonError(error);}
}
export async function POST(request:Request) {
  try {checkOrigin(request);await requireAdmin();const input=await jsonBody(request,2048);
    if(input.reviewConfirmed!==true)throw new HttpError(400,"외부 증빙 확인과 글 작성 승인 여부를 확인해주세요.");
    if(input.writerID!==undefined&&!uuid.safeParse(input.writerID).success)throw new HttpError(400,"작성 권한 ID를 확인해주세요.");
    return reply(await newGrant(input.writerID),201);
  }catch(error){return jsonError(error);}
}

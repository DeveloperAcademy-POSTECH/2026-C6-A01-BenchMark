import { jsonBody, limitedIP, redeem, reply, writer } from "@/lib/campus";
import { database } from "@/lib/db";
import { jsonError } from "@/lib/security";
export async function POST(request:Request) {
  try {await limitedIP(request,"redeem");const input=await jsonBody(request,2048);return reply(await redeem(input.code));}
  catch(error){return jsonError(error);}
}
export async function DELETE(request:Request) {
  try {const id=await writer(request);await database().query("UPDATE campus_writers SET token_hash=NULL,token_expires_at=NULL WHERE id=$1",[id]);return reply({ok:true});}
  catch(error){return jsonError(error);}
}

import { campusInput, digest, fields, inputValues, jsonBody, reply, uuid, writer } from "@/lib/campus";
import { database } from "@/lib/db";
import { HttpError, jsonError, rateLimit } from "@/lib/security";
export const dynamic="force-dynamic";
export async function GET(request:Request) {
  try {
    const q=new URL(request.url).searchParams,cursor=q.get("cursor");
    if(cursor&&!uuid.safeParse(cursor).success) throw new HttpError(400,"조회 기준을 확인해주세요.");
    const box=["south","west","north","east"].map(k=>q.get(k));
    if(box.some(v=>v!==null)&&!box.every(v=>v!==null&&v.trim()!==""&&Number.isFinite(Number(v)))) throw new HttpError(400,"지도 범위를 확인해주세요.");
    const [south,west,north,east]=box[0]===null?[-90,-180,90,180]:box.map(Number);
    if(south>north||west>east||south< -90||north>90||west< -180||east>180) throw new HttpError(400,"지도 범위를 확인해주세요.");
    const result=await database().query(`SELECT ${fields} FROM campus_ois o JOIN campus_writers w ON w.id=o.writer_id
      WHERE o.status='published' AND w.revoked_at IS NULL AND ($1::uuid IS NULL OR o.id>$1)
      AND o.latitude BETWEEN $2 AND $3 AND o.longitude BETWEEN $4 AND $5 ORDER BY o.id LIMIT 201`,[cursor,south,north,west,east]);
    const items=result.rows.slice(0,200);return reply({items,nextCursor:result.rows.length>200?items.at(-1).id:null});
  }catch(error){return jsonError(error);}
}
export async function POST(request:Request) {
  try {
    const owner=await writer(request);await rateLimit(`campus:write:${owner}`,60,60);
    const parsed=campusInput.safeParse(await jsonBody(request));
    if(!parsed.success) throw new HttpError(400,parsed.error.issues[0].message);
    const p=parsed.data,h=digest(JSON.stringify(p));
    const inserted=await database().query(`INSERT INTO campus_ois(id,writer_id,campus_id,model,latitude,longitude,height_meters,heading_degrees,display_name,title,story,request_hash)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT(id) DO NOTHING RETURNING id,status,revision`,[p.id,owner,...inputValues(p),h]);
    let saved=inserted.rows[0];
    if(!inserted.rowCount) {
      const existing=await database().query("SELECT id,status,revision FROM campus_ois WHERE id=$1 AND writer_id=$2 AND request_hash=$3",[p.id,owner,h]);
      saved=existing.rows[0];
      if(!existing.rowCount) throw new HttpError(409,"같은 요청 번호의 내용이 달라졌습니다. 새 요청으로 저장해주세요.");
    }
    return reply(saved,inserted.rowCount?201:200);
  }catch(error){return jsonError(error);}
}

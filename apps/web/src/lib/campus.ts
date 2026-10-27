import { createHash, randomBytes, randomUUID } from "node:crypto";
import { z } from "zod";
import geometry from "./campus-geometry.json";
import { database } from "./db";
import { boundedBody, hash, HttpError, rateLimit } from "./security";

// Same WGS84 ECEF -> ENU XY as CampusGeoreference.swift. No mesh height is stored as AR altitude.
export function campusXY(latitude: number, longitude: number): [number, number] {
  const rad = Math.PI / 180, a = 6378137, e2 = 0.0066943799901413165;
  function ecef(lon: number, lat: number) {
    const l=lon*rad,p=lat*rad,n=a/Math.sqrt(1-e2*Math.sin(p)**2);
    return [n*Math.cos(p)*Math.cos(l),n*Math.cos(p)*Math.sin(l),n*(1-e2)*Math.sin(p)];
  }
  const [lon,lat]=geometry.origin,l=lon*rad,p=lat*rad;
  const o=ecef(lon,lat),v=ecef(longitude,latitude).map((n,i)=>n-o[i]);
  return [(-Math.sin(l)*v[0]+Math.cos(l)*v[1])*geometry.unitsPerMeter,
    (-Math.sin(p)*Math.cos(l)*v[0]-Math.sin(p)*Math.sin(l)*v[1]+Math.cos(p)*v[2])*geometry.unitsPerMeter];
}
function inside([x,y]: number[], polygon: number[][]) {
  let result=false;
  for(let i=0,j=polygon.length-1;i<polygon.length;j=i++) {
    const a=polygon[i],b=polygon[j];
    if((a[1]>y)!==(b[1]>y) && x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]) result=!result;
  }
  return result;
}
export function allowedCampusPosition(latitude: number, longitude: number) {
  if(!Number.isFinite(latitude)||!Number.isFinite(longitude)||Math.abs(latitude)>90||Math.abs(longitude)>180) return false;
  const point=campusXY(latitude,longitude);
  return geometry.bounds.some(p=>inside(point,p)) && !geometry.buildings.some(p=>inside(point,p));
}
export const campusInput=z.object({
  id:z.string().uuid(), campusID:z.literal("postech"), model:z.literal("helmet-oi"),
  latitude:z.number().finite().min(-90).max(90), longitude:z.number().finite().min(-180).max(180),
  heightMeters:z.number().finite().min(.4).max(2), headingDegrees:z.number().finite().min(0).lt(360),
  displayName:z.string().trim().min(1).max(40), title:z.string().trim().min(1).max(80), story:z.string().trim().min(1).max(2000),
}).strict().refine(v=>allowedCampusPosition(v.latitude,v.longitude),"캠퍼스 경계 안의 건물 밖 공간을 선택해주세요.");
export type CampusInput=z.infer<typeof campusInput>;
export const uuid=z.string().uuid();
export const digest=(text:string)=>createHash("sha256").update(text).digest("hex");
export const opaqueToken=()=>randomBytes(32).toString("base64url");
export const publicHeaders={"Cache-Control":"private, no-store"};
export const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:publicHeaders});
export async function jsonBody(request:Request,maximum=16000) {
  if(!request.headers.get("content-type")?.startsWith("application/json")) throw new HttpError(415,"JSON 형식이 필요합니다.");
  const bytes=await boundedBody(request,maximum);
  try {
    const body=JSON.parse(bytes.toString());
    if(!body || typeof body!=="object" || Array.isArray(body)) throw new Error();
    return body;
  }catch{throw new HttpError(400,"요청 형식을 확인해주세요.");}
}
export async function limitedIP(request:Request,kind:string,maximum=15) {
  const ip=request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim()||"unknown";
  await rateLimit(`campus:${kind}:${hash(ip)}`,maximum,900);
}
export async function writer(request:Request) {
  const match=/^Bearer ([A-Za-z0-9_-]{43})$/.exec(request.headers.get("authorization")||"");
  if(!match) throw new HttpError(401,"작성 코드를 등록하거나 다시 발급받아주세요.");
  const row=await database().query("SELECT id FROM campus_writers WHERE token_hash=$1 AND token_expires_at>now() AND revoked_at IS NULL",[digest(match[1])]);
  if(!row.rowCount) throw new HttpError(401,"작성 권한이 만료되었거나 취소되었습니다.");
  return row.rows[0].id as string;
}
export async function newGrant(existingID?:string) {
  const id=existingID||randomUUID(),code=opaqueToken();
  if(existingID) {
    const updated=await database().query("UPDATE campus_writers SET code_hash=$1,code_expires_at=now()+interval '24 hours',redeemed_at=NULL,token_hash=NULL,token_expires_at=NULL WHERE id=$2 AND revoked_at IS NULL RETURNING id",[digest(code),id]);
    if(!updated.rowCount)throw new HttpError(404,"취소되었거나 없는 작성 권한입니다.");
  } else await database().query("INSERT INTO campus_writers(id,code_hash,code_expires_at) VALUES($1,$2,now()+interval '24 hours')",[id,digest(code)]);
  return {id,code,expiresInSeconds:86400};
}
export async function redeem(code:unknown) {
  if(typeof code!=="string"||!/^[A-Za-z0-9_-]{43}$/.test(code)) throw new HttpError(401,"작성 코드가 올바르지 않습니다.");
  const token=opaqueToken();
  const result=await database().query(`UPDATE campus_writers SET redeemed_at=now(),token_hash=$1,token_expires_at=now()+interval '30 days'
    WHERE code_hash=$2 AND redeemed_at IS NULL AND revoked_at IS NULL AND code_expires_at>now() RETURNING id,token_expires_at`,[digest(token),digest(code)]);
  if(!result.rowCount) throw new HttpError(401,"사용했거나 만료된 코드입니다. 운영진에게 재발급을 요청해주세요.");
  return {writerID:result.rows[0].id,token,expiresAt:result.rows[0].token_expires_at};
}
export const fields=`o.id, o.id AS "storyID", o.campus_id AS "campusID", o.model, o.latitude, o.longitude,
 o.height_meters AS "heightMeters", o.heading_degrees AS "headingDegrees", o.display_name AS "displayName",
 o.title, o.story, o.status, o.revision, o.updated_at AS "updatedAt"`;
export function inputValues(p:CampusInput) {return [p.campusID,p.model,p.latitude,p.longitude,p.heightMeters,p.headingDegrees,p.displayName,p.title,p.story];}

import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { bindings } from "./sites-storage";
import { boundedBody, HttpError } from "./security";

const maxBytes = 5 * 1024 * 1024;
export function photoKey(kind: "job" | "source") {
  const wrappingKey = process.env.SESSION_WRAP_KEY;
  if (!wrappingKey || wrappingKey.length < 32) throw new HttpError(503, "사진 처리 설정을 확인해주세요.");
  return createHash("sha256").update(`benchmark-photo-${kind}-v1\0${wrappingKey}`).digest("hex");
}
export function sourceSignature(timestamp: string, id: string) {
  return createHmac("sha256", photoKey("source")).update(`photo-source-v1\n${timestamp}\n${id}`).digest("base64url");
}
export async function servePhotoSource(request: Request, id: string) {
  const timestamp = request.headers.get("x-photo-timestamp") || "";
  const signature = request.headers.get("x-photo-signature") || "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(id) ||
      request.headers.get("x-photo-id") !== id || !/^\d{10}$/.test(timestamp) ||
      Math.abs(Date.now() / 1000 - Number(timestamp)) > 120 || !/^[A-Za-z0-9_-]{43}$/.test(signature) ||
      !timingSafeEqual(Buffer.from(signature), Buffer.from(sourceSignature(timestamp,id)))) {
    throw new HttpError(401, "사진 처리 요청을 확인해주세요.");
  }
  const { db, bucket } = bindings();
  const row = await db.prepare("UPDATE photo_jobs SET consumed=1 WHERE id=? AND consumed=0 AND expires_at>? RETURNING object_key")
    .bind(id,Date.now()).first<{object_key:string}>();
  if (!row) throw new HttpError(410, "사진 처리 요청이 만료되었습니다.");
  const object = await bucket.get(row.object_key);
  if (!object) throw new HttpError(410, "사진 처리 요청이 만료되었습니다.");
  return new Response(object.body,{headers:{"Content-Type":"application/octet-stream","Content-Length":String(object.size),
    "Cache-Control":"no-store","X-Content-Type-Options":"nosniff","x-photo-job-id":id}});
}
export async function processPhoto(input: Uint8Array) {
  if (input.byteLength > maxBytes) throw new HttpError(413, "사진은 5MB 이하로 올려주세요.");
  let endpoint: URL;
  try { endpoint = new URL(process.env.PHOTO_PROCESSOR_URL || ""); } catch { throw new HttpError(503,"사진 처리 설정을 확인해주세요."); }
  if (endpoint.protocol !== "https:" || endpoint.username || endpoint.password || !endpoint.hostname.endsWith(".netlify.app") ||
      endpoint.pathname !== "/.netlify/functions/photo" || endpoint.search || endpoint.hash) throw new HttpError(503,"사진 처리 설정을 확인해주세요.");
  const { db, bucket } = bindings();
  const id = randomUUID(); const key = `photo-jobs/${id}`;
  await bucket.put(key,input);
  let stage = "register";
  try {
    await db.prepare("INSERT INTO photo_jobs(id,object_key,expires_at,consumed) VALUES(?,?,?,0)").bind(id,key,Date.now()+120000).run();
    const body = JSON.stringify({jobId:id,sha256:createHash("sha256").update(input).digest("hex")});
    const timestamp = String(Math.floor(Date.now()/1000));
    const signature = createHmac("sha256",photoKey("job"))
      .update(`photo-request-v1\n${timestamp}\n${id}\n${createHash("sha256").update(body).digest("hex")}`).digest("base64url");
    stage = "processor";
    const response = await fetch(endpoint.href,{method:"POST",redirect:"manual",cache:"no-store",signal:AbortSignal.timeout(55000),
      headers:{"Content-Type":"application/json","x-photo-id":id,"x-photo-timestamp":timestamp,"x-photo-signature":signature},body});
    if (!response.ok) {
      console.error("Photo processor rejected a request.",{status:response.status});
      await response.body?.cancel();
      if (response.status === 400) throw new HttpError(400,"JPG, PNG, WebP 정지 사진을 올려주세요.");
      if (response.status === 413) throw new HttpError(413,"사진은 5MB 이하로 올려주세요.");
      throw new HttpError(503,"사진을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.");
    }
    if (response.headers.get("content-type") !== "image/jpeg") { await response.body?.cancel(); throw new HttpError(503,"사진을 처리하지 못했습니다."); }
    stage = "read-result";
    const output = await boundedBody(new Request("https://photo-response.local",{method:"POST",body:response.body,duplex:"half"} as RequestInit),maxBytes);
    if (output.length < 3 || output[0] !== 255 || output[1] !== 216 || output[2] !== 255) throw new HttpError(503,"사진을 처리하지 못했습니다.");
    return output;
  } catch(error) {
    console.error("Photo processing failed.",{stage,kind:error instanceof Error?error.name:typeof error});
    throw error;
  } finally {
    await db.prepare("DELETE FROM photo_jobs WHERE id=?").bind(id).run();
    await bucket.delete(key);
  }
}

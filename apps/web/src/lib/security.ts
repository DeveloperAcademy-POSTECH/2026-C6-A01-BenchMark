import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { database } from "./db";

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export const sessionCookie = "mat_admin";
export function secret() {
  const value = process.env.SESSION_SECRET;
  if (!value || value.length < 32) throw new HttpError(503, "운영 설정을 확인해주세요.");
  return value;
}
function password() {
  const value = process.env.ADMIN_PASSWORD;
  if (!value || value.length < 9) throw new HttpError(503, "관리자 비밀번호 설정을 확인해주세요.");
  return value;
}
export function hash(value: string) { return createHmac("sha256", secret()).update(value).digest("hex"); }
export function correctPassword(candidate: string) {
  return timingSafeEqual(createHash("sha256").update(candidate).digest(), createHash("sha256").update(password()).digest());
}
export function makeSession(now = Date.now()) {
  const expires = String(now + 8 * 60 * 60 * 1000);
  return `${expires}.${hash(`${expires}:${password()}`)}`;
}
export function validSession(token: string | undefined, now = Date.now()) {
  if (!token) return false;
  const [expires, signature] = token.split(".");
  if (!/^\d{13}$/.test(expires ?? "") || !/^[a-f0-9]{64}$/.test(signature ?? "")) return false;
  if (Number(expires) <= now || Number(expires) > now + 8 * 60 * 60 * 1000) return false;
  return timingSafeEqual(Buffer.from(signature, "hex"), Buffer.from(hash(`${expires}:${password()}`), "hex"));
}
export async function isAdmin() { return validSession((await cookies()).get(sessionCookie)?.value); }
export async function requireAdmin() {
  if (!await isAdmin()) throw new HttpError(401, "다시 로그인해주세요.");
}
export function checkOrigin(request: Request) {
  const expected = process.env.APP_ORIGIN || new URL(request.url).origin;
  if (request.headers.get("origin") !== expected) throw new HttpError(403, "요청 출처를 확인할 수 없습니다.");
}
export async function rateLimit(key: string, maximum: number, seconds: number) {
  const result = await database().query(`INSERT INTO mat_rate_limits(key,window_start,attempts) VALUES($1,now(),1)
    ON CONFLICT(key) DO UPDATE SET
      attempts=CASE WHEN mat_rate_limits.window_start < now()-make_interval(secs => $2) THEN 1 ELSE mat_rate_limits.attempts+1 END,
      window_start=CASE WHEN mat_rate_limits.window_start < now()-make_interval(secs => $2) THEN now() ELSE mat_rate_limits.window_start END
    RETURNING attempts`, [key, seconds]);
  if (result.rows[0].attempts > maximum) throw new HttpError(429, "요청이 많습니다. 잠시 후 다시 시도해주세요.");
}
export function jsonError(error: unknown) {
  if (error instanceof HttpError) return Response.json({ error: error.message }, { status: error.status });
  console.error("Story operation failed.");
  return Response.json({ error: "처리하지 못했습니다. 잠시 후 다시 시도해주세요." }, { status: 503 });
}
export async function boundedBody(request: Request, maximum: number) {
  if (Number(request.headers.get("content-length")) > maximum) throw new HttpError(413, "파일 또는 요청 크기가 너무 큽니다.");
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, "내용을 입력해주세요.");
  const chunks: Uint8Array[] = []; let length = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read(); if (done) break;
      length += value.byteLength;
      if (length > maximum) { await reader.cancel(); throw new HttpError(413, "파일 또는 요청 크기가 너무 큽니다."); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks);
}

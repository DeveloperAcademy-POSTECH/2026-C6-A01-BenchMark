import { database } from "@/lib/db";
import { collectionPolicy } from "@/lib/config";
import { registrationSchema, fieldErrors } from "@/lib/registration";
import { saveRegistration } from "@/lib/save-registration";

export const runtime = "nodejs";
const json = (body: unknown, status: number) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });

export async function POST(request: Request) {
  const expectedOrigin = process.env.APP_ORIGIN;
  if (!expectedOrigin) return json({ message: "접수를 준비 중이에요. 잠시 후 다시 시도해주세요." }, 503);
  if (request.headers.get("origin") !== expectedOrigin) return json({ message: "신청 페이지에서 다시 시도해주세요." }, 403);
  if (!request.headers.get("content-type")?.startsWith("application/json")) return json({ message: "요청 형식을 확인해주세요." }, 415);
  let payload: unknown;
  try {
    const reader = request.body?.getReader();
    if (!reader) return json({ message: "입력 내용을 확인해주세요." }, 400);
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 4096) { await reader.cancel(); return json({ message: "입력 내용이 너무 길어요." }, 413); }
      chunks.push(value);
    }
    payload = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch { return json({ message: "입력 내용을 확인해주세요." }, 400); }
  const parsed = registrationSchema.safeParse(payload);
  if (!parsed.success) return json({ message: "입력 내용을 확인해주세요.", errors: fieldErrors(parsed.error) }, 422);
  try {
    const policy = collectionPolicy();
    if (policy.mode === "test" && !/^0100000\d{4}$/.test(parsed.data.phone)) {
      return json({ message: "테스트용 번호를 입력해주세요.", errors: { phone: "테스트에서는 010-0000-숫자 4자리 형식만 사용해주세요." } }, 422);
    }
    const result = await saveRegistration(database(), parsed.data, policy.retentionDays);
    if (result === "limited") return json({ message: "잠시 신청이 몰리고 있어요. 1분 후 다시 시도해주세요." }, 429);
    return json({ message: "신청이 접수됐어요." }, 200);
  } catch {
    // Never emit a database error, connection string, or submitted personal data.
    return json({ message: "지금은 접수를 완료할 수 없어요. 입력 내용은 유지되니 잠시 후 다시 시도해주세요." }, 503);
  }
}

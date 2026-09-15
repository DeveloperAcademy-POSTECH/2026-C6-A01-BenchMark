import { database } from "@/lib/db";
import { reservationInput } from "@/lib/reservation";
import { readMultipart, readPhoto } from "@/lib/upload";
import { checkOrigin, hash, HttpError, jsonError, rateLimit } from "@/lib/security";

export async function POST(request: Request) {
  try {
    checkOrigin(request);
    const ip = request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim() || "local";
    await rateLimit(`reservation:${hash(ip)}`, 10, 900);
    await rateLimit("reservation:global", 100, 900);
    const form = await readMultipart(request);
    const parsed = reservationInput.safeParse({ ...Object.fromEntries(form), sourceStoryId: form.get("sourceStoryId") || undefined });
    if (!parsed.success) throw new HttpError(400, parsed.error.issues[0].message);
    const d = parsed.data;
    const photo = await readPhoto(form);
    if (!photo) throw new HttpError(400, "사진 한 장을 올려주세요.");
    const inserted = await database().query(`INSERT INTO mat_reservations(id,display_name,phone,reason,reason_other,title,story,photo,payment_method,amount,source_story_id)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,(SELECT id FROM mat_stories WHERE id=$11 AND published AND payment_verified))
      ON CONFLICT (id) DO NOTHING RETURNING id`, [d.id, d.displayName, d.phone, d.reason, d.reason === "other" ? d.reasonOther : "", d.title, d.story, photo, d.paymentMethod, d.amount, d.sourceStoryId || null]);
    if (!inserted.rowCount) {
      const existing = await database().query(`SELECT 1 FROM mat_reservations WHERE id=$1 AND display_name=$2 AND phone=$3 AND reason=$4
        AND reason_other=$5 AND title=$6 AND story=$7 AND photo=$8 AND payment_method=$9 AND amount=$10`,
      [d.id, d.displayName, d.phone, d.reason, d.reason === "other" ? d.reasonOther : "", d.title, d.story, photo, d.paymentMethod, d.amount]);
      if (!existing.rowCount) throw new HttpError(409, "이 접수번호로 이미 다른 내용이 접수됐습니다. 새로고침 후 확인해주세요.");
    }
    return Response.json({ id: d.id }, { status: 201, headers: { "Cache-Control": "no-store" } });
  } catch (error) { return jsonError(error); }
}

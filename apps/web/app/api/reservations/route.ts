import { bindings, loadPhoto, storePhoto } from "@/lib/sites-storage";
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
    const existing = await database().query<{photo:string}>(`SELECT photo FROM mat_reservations WHERE id=$1 AND display_name=$2 AND email=$3 AND reason=$4
      AND reason_other=$5 AND title=$6 AND story=$7 AND payment_method=$8 AND amount=$9`,
      [d.id,d.displayName,d.email,d.reason,d.reason === "other" ? d.reasonOther : "",d.title,d.story,d.paymentMethod,d.amount]);
    if (existing.rowCount) {
      if (!(await loadPhoto(existing.rows[0].photo)).equals(photo)) throw new HttpError(409,"이 접수번호로 이미 다른 내용이 접수됐습니다. 새로고침 후 확인해주세요.");
    } else {
      const key = await storePhoto(photo);
      let inserted = false;
      try {
        const result = await database().query(`INSERT INTO mat_reservations(id,display_name,email,reason,reason_other,title,story,photo,payment_method,amount,source_story_id)
          VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,(SELECT id FROM mat_stories WHERE id=$11 AND published AND payment_verified))
          ON CONFLICT(id) DO NOTHING RETURNING id`,[d.id,d.displayName,d.email,d.reason,d.reason === "other" ? d.reasonOther : "",d.title,d.story,key,d.paymentMethod,d.amount,d.sourceStoryId || null]);
        inserted = !!result.rowCount;
        if (!inserted) {
          const retry = await database().query<{photo:string}>(`SELECT photo FROM mat_reservations WHERE id=$1 AND display_name=$2 AND email=$3 AND reason=$4
            AND reason_other=$5 AND title=$6 AND story=$7 AND payment_method=$8 AND amount=$9`,
            [d.id,d.displayName,d.email,d.reason,d.reason === "other" ? d.reasonOther : "",d.title,d.story,d.paymentMethod,d.amount]);
          if (!retry.rowCount || !(await loadPhoto(retry.rows[0].photo)).equals(photo)) throw new HttpError(409,"이 접수번호로 이미 다른 내용이 접수됐습니다. 새로고침 후 확인해주세요.");
        }
      } finally { if (!inserted) await bindings().bucket.delete(key); }
    }
    return Response.json({ id: d.id }, { status: 201, headers: { "Cache-Control": "no-store" } });
  } catch (error) { return jsonError(error); }
}

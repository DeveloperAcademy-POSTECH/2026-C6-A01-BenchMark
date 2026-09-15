import { randomUUID } from "node:crypto";
import { database } from "./db";
import { storyInput } from "./story";
import { readMultipart, readPhoto } from "./upload";
import { HttpError } from "./security";

export async function readStoryForm(request: Request, creating: boolean) {
  const form = await readMultipart(request);
  const parsed = storyInput.safeParse({
    title: form.get("title") || "", reservationId: form.get("reservationId") || undefined,
    matNumber: form.get("matNumber"), matSize: form.get("matSize"), displayName: form.get("displayName"), story: form.get("story"),
    paymentVerified: form.get("paymentVerified") === "true", published: form.get("published") === "true",
    revision: form.get("revision") || undefined,
  });
  if (!parsed.success) throw new HttpError(400, parsed.error.issues[0].message);
  if (!creating && !parsed.data.revision) throw new HttpError(400, "화면을 새로고침한 뒤 수정해주세요.");
  const photo = await readPhoto(form);
  if (creating && !photo && !parsed.data.reservationId) throw new HttpError(400, "사진 한 장을 올려주세요.");
  return { data: parsed.data, photo };
}
export async function saveStory(request: Request, id?: string) {
  const { data, photo: uploadedPhoto } = await readStoryForm(request, !id);
  const client = await database().connect();
  try {
    await client.query("BEGIN");
    let photo = uploadedPhoto;
    if (data.reservationId) {
      if (id) throw new HttpError(400, "예약은 새 이야기에만 연결할 수 있습니다.");
      const reserved = await client.query("SELECT photo,story_id FROM mat_reservations WHERE id=$1 FOR UPDATE", [data.reservationId]);
      if (!reserved.rowCount) throw new HttpError(404, "예약을 찾을 수 없습니다.");
      if (reserved.rows[0].story_id) throw new HttpError(409, "이미 이야기로 등록된 예약입니다.");
      photo ??= reserved.rows[0].photo;
    }
    const values = [data.matNumber, data.matSize, data.displayName, data.story, data.paymentVerified, data.published, photo, data.title];
    if (id) {
      const result = await client.query(`UPDATE mat_stories SET mat_number=$1,mat_size=$2,display_name=$3,story=$4,
        payment_verified=$5,published=$6,photo=COALESCE($7,photo),title=$8,revision=revision+1,updated_at=now()
        WHERE id=$9 AND revision=$10 RETURNING id`, [...values, id, data.revision]);
      if (!result.rowCount) throw new HttpError(409, "다른 관리자가 수정했거나 삭제했습니다. 새로고침 후 확인해주세요.");
    } else {
      id = randomUUID();
      await client.query(`INSERT INTO mat_stories(mat_number,mat_size,display_name,story,payment_verified,published,photo,title,id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, [...values, id]);
    }
    if (data.reservationId) await client.query("UPDATE mat_reservations SET story_id=$1 WHERE id=$2", [id, data.reservationId]);
    await client.query("COMMIT");
    return id;
  } catch (error) {
    await client.query("ROLLBACK");
    if ((error as { code?: string }).code === "23505") throw new HttpError(409, "이미 등록된 돗자리 번호입니다.");
    throw error;
  } finally { client.release(); }
}

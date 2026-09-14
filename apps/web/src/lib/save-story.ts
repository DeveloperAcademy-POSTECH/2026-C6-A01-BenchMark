import { randomUUID } from "node:crypto";
import sharp from "sharp";
import { database } from "./db";
import { storyInput } from "./story";
import { boundedBody, HttpError } from "./security";

export async function readStoryForm(request: Request, creating: boolean) {
  const bytes = await boundedBody(request, 6 * 1024 * 1024);
  let form;
  try { form = await new Response(new Uint8Array(bytes), { headers: { "content-type": request.headers.get("content-type") || "" } }).formData(); }
  catch { throw new HttpError(400, "입력 형식을 확인해주세요."); }
  const parsed = storyInput.safeParse({
    matNumber: form.get("matNumber"), matSize: form.get("matSize"), displayName: form.get("displayName"), story: form.get("story"),
    paymentVerified: form.get("paymentVerified") === "true", published: form.get("published") === "true",
    revision: form.get("revision") || undefined,
  });
  if (!parsed.success) throw new HttpError(400, parsed.error.issues[0].message);
  if (!creating && !parsed.data.revision) throw new HttpError(400, "화면을 새로고침한 뒤 수정해주세요.");
  const file = form.get("photo"); let photo: Buffer | null = null;
  if (file instanceof File && file.size > 0) {
    if (file.size > 5 * 1024 * 1024) throw new HttpError(413, "사진은 5MB 이하로 올려주세요.");
    try {
      const input = Buffer.from(await file.arrayBuffer());
      const metadata = await sharp(input, { limitInputPixels: 40000000 }).metadata();
      if (!["jpeg", "png", "webp"].includes(metadata.format || "") || (metadata.pages || 1) > 1) throw new Error("Unsupported photo");
      photo = await sharp(input, { limitInputPixels: 40000000 }).rotate().resize(1600, 1600, { fit: "inside", withoutEnlargement: true }).jpeg({ quality: 85 }).toBuffer();
    } catch { throw new HttpError(400, "JPG, PNG, WebP 정지 사진을 올려주세요."); }
  }
  if (creating && !photo) throw new HttpError(400, "사진 한 장을 올려주세요.");
  return { data: parsed.data, photo };
}
export async function saveStory(request: Request, id?: string) {
  const { data, photo } = await readStoryForm(request, !id);
  const values = [data.matNumber, data.matSize, data.displayName, data.story, data.paymentVerified, data.published, photo];
  try {
    if (id) {
      const result = await database().query(`UPDATE mat_stories SET mat_number=$1,mat_size=$2,display_name=$3,story=$4,
        payment_verified=$5,published=$6,photo=COALESCE($7,photo),revision=revision+1,updated_at=now()
        WHERE id=$8 AND revision=$9 RETURNING id`, [...values, id, data.revision]);
      if (!result.rowCount) throw new HttpError(409, "다른 관리자가 수정했거나 삭제했습니다. 새로고침 후 확인해주세요.");
    } else {
      id = randomUUID();
      await database().query(`INSERT INTO mat_stories(mat_number,mat_size,display_name,story,payment_verified,published,photo,id)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, [...values, id]);
    }
    return id;
  } catch (error) {
    if ((error as { code?: string }).code === "23505") throw new HttpError(409, "이미 등록된 돗자리 번호입니다.");
    throw error;
  }
}

import sharp from "sharp";
import { boundedBody, HttpError } from "./security";

export async function readMultipart(request: Request) {
  const bytes = await boundedBody(request, 6 * 1024 * 1024);
  let form;
  try { form = await new Response(new Uint8Array(bytes), { headers: { "content-type": request.headers.get("content-type") || "" } }).formData(); }
  catch { throw new HttpError(400, "입력 형식을 확인해주세요."); }
  return form;
}
export async function readPhoto(form: FormData) {
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
  return photo;
}

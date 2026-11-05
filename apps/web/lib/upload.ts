import { processPhoto } from "./photo-jobs";
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
    photo = await processPhoto(new Uint8Array(await file.arrayBuffer()));
  }
  return photo;
}

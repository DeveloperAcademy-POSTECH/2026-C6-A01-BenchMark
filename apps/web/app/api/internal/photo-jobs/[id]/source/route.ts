import { servePhotoSource } from "@/lib/photo-jobs";
import { jsonError } from "@/lib/security";

export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  try { return await servePhotoSource(request,(await context.params).id); }
  catch (error) { return jsonError(error); }
}

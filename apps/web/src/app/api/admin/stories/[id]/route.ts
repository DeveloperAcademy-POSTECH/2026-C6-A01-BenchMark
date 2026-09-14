import { database } from "@/lib/db";
import { boundedBody, checkOrigin, HttpError, jsonError, requireAdmin } from "@/lib/security";
import { saveStory } from "@/lib/save-story";
import { uuid } from "@/lib/story";

type Context = { params: Promise<{ id: string }> };
export async function PUT(request: Request, context: Context) {
  try {
    checkOrigin(request); await requireAdmin();
    const { id } = await context.params;
    if (!uuid.safeParse(id).success) throw new HttpError(404, "이야기를 찾을 수 없습니다.");
    return Response.json({ id: await saveStory(request, id) });
  } catch (error) { return jsonError(error); }
}
export async function DELETE(request: Request, context: Context) {
  try {
    checkOrigin(request); await requireAdmin(); const { id } = await context.params;
    if (!uuid.safeParse(id).success) throw new HttpError(404, "이야기를 찾을 수 없습니다.");
    let revision;
    try { revision = JSON.parse((await boundedBody(request, 1024)).toString()).revision; }
    catch { throw new HttpError(400, "요청을 확인해주세요."); }
    if (!Number.isInteger(revision) || revision < 1) throw new HttpError(400, "새로고침 후 다시 시도해주세요.");
    const result = await database().query("DELETE FROM mat_stories WHERE id=$1 AND revision=$2", [id, revision]);
    if (!result.rowCount) throw new HttpError(409, "내용이 변경되었습니다. 새로고침 후 확인해주세요.");
    return Response.json({ ok: true });
  } catch (error) { return jsonError(error); }
}

import { bindings } from "@/lib/sites-storage";
import { database } from "@/lib/db";
import { checkOrigin, HttpError, jsonError, requireAdmin } from "@/lib/security";
import { uuid } from "@/lib/story";

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    checkOrigin(request); await requireAdmin();
    const { id } = await params;
    if (!uuid.safeParse(id).success) throw new HttpError(404, "예약을 찾을 수 없습니다.");
    const deleted = await database().query<{photo:string}>("DELETE FROM mat_reservations WHERE id=$1 RETURNING photo", [id]);
    if (deleted.rows[0]) await bindings().bucket.delete(deleted.rows[0].photo);
    return Response.json({ ok: true });
  } catch (error) { return jsonError(error); }
}

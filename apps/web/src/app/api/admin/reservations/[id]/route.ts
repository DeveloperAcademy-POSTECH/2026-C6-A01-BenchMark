import { database } from "@/lib/db";
import { checkOrigin, HttpError, jsonError, requireAdmin } from "@/lib/security";
import { uuid } from "@/lib/story";

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    checkOrigin(request); await requireAdmin();
    const { id } = await params;
    if (!uuid.safeParse(id).success) throw new HttpError(404, "예약을 찾을 수 없습니다.");
    await database().query("DELETE FROM mat_reservations WHERE id=$1", [id]);
    return Response.json({ ok: true });
  } catch (error) { return jsonError(error); }
}

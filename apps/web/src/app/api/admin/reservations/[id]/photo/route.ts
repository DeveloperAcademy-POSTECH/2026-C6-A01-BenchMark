import { database } from "@/lib/db";
import { jsonError, requireAdmin } from "@/lib/security";
import { uuid } from "@/lib/story";
export const dynamic = "force-dynamic";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await requireAdmin(); const { id } = await params;
    if (!uuid.safeParse(id).success) return new Response(null, { status: 404 });
    const result = await database().query("SELECT photo FROM mat_reservations WHERE id=$1", [id]);
    if (!result.rowCount) return new Response(null, { status: 404 });
    return new Response(new Uint8Array(result.rows[0].photo), { headers: { "Content-Type": "image/jpeg", "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" } });
  } catch (error) { return jsonError(error); }
}

import { loadPhoto } from "@/lib/sites-storage";
import { database } from "@/lib/db";
import { isAdmin, jsonError } from "@/lib/security";
import { uuid } from "@/lib/story";

export const dynamic = "force-dynamic";
export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    if (!uuid.safeParse(id).success) return new Response(null, { status: 404 });
    const result = await database().query<{photo:string;published:boolean;payment_verified:boolean}>("SELECT photo,published,payment_verified FROM mat_stories WHERE id=$1", [id]);
    const row = result.rows[0];
    if (!row || (!(row.published && row.payment_verified) && !await isAdmin())) return new Response(null, { status: 404 });
    return new Response(new Uint8Array(await loadPhoto(row.photo)), { headers: { "Content-Type": "image/jpeg", "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" } });
  } catch (error) { return jsonError(error); }
}

import { database } from "@/lib/db";
import { collectionPolicy } from "@/lib/config";
export const dynamic = "force-dynamic";
export async function GET() {
  try {
    collectionPolicy();
    if (!process.env.APP_ORIGIN) throw new Error("Missing origin");
    await database().query("SELECT id FROM registrations LIMIT 0");
    return Response.json({ status: "ok" });
  } catch { return Response.json({ status: "unavailable" }, { status: 503 }); }
}

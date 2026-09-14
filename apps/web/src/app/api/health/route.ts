import { database } from "@/lib/db";
import { secret } from "@/lib/security";
export const dynamic = "force-dynamic";
export async function GET() {
  try {
    secret();
    if (!process.env.ADMIN_PASSWORD || process.env.ADMIN_PASSWORD.length < 12) throw new Error("Missing password");
    if (process.env.NODE_ENV === "production" && !process.env.APP_ORIGIN) throw new Error("Missing origin");
    await database().query("SELECT 1 FROM mat_stories LIMIT 1");
    return Response.json({ status: "ok" });
  } catch { return Response.json({ status: "unavailable" }, { status: 503 }); }
}

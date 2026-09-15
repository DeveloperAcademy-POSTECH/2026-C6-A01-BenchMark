import { csvActivity } from "@/lib/activity";
import { queryActivity } from "@/lib/activity-store";
import { jsonError, rateLimit, requireAdmin } from "@/lib/security";
export async function GET(request: Request) {
  try {
    await requireAdmin();
    await rateLimit("activity:admin", 60, 60);
    const result = await queryActivity(new URL(request.url).searchParams);
    if (result.format === "csv") return new Response(csvActivity(result.rows), { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": 'attachment; filename="page-activity.csv"', "Cache-Control": "private, no-store" } });
    return Response.json(result, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return jsonError(error); }
}

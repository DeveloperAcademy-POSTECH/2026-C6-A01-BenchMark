import { z } from "zod";
import { activityEvent } from "@/lib/activity";
import { database } from "@/lib/db";
import { boundedBody, checkOrigin, excludeAdminActivity, HttpError, jsonError, rateLimit } from "@/lib/security";

export async function POST(request: Request) {
  try {
    checkOrigin(request);
    if (await excludeAdminActivity()) return Response.json({ accepted: 0 }, { headers: { "Cache-Control": "private, no-store" } });
    await rateLimit("activity:global", 600, 60);
    let body: unknown;
    try { body = JSON.parse((await boundedBody(request, 16384)).toString()); }
    catch (error) { if (error instanceof HttpError) throw error; throw new HttpError(400, "로그 형식을 확인해주세요."); }
    const parsed = z.object({ events: z.array(activityEvent).min(1).max(20) }).strict().safeParse(body);
    if (!parsed.success) throw new HttpError(400, "허용된 활동 로그만 전송해주세요.");
    const events = parsed.data.events;
    const now = Date.now();
    if (events.some(e => e.sessionId !== events[0].sessionId || Date.parse(e.occurredAt) < now - 86400000 || Date.parse(e.occurredAt) > now + 60000)) throw new HttpError(400, "세션 또는 발생 시각을 확인해주세요.");
    await rateLimit(`activity:session:${events[0].sessionId}`, 120, 60);
    const storyIds = [...new Set(events.flatMap(e => [e.storyId, e.name === "link_click" ? e.properties.targetStoryId : undefined].filter((id): id is string => !!id)))];
    const client = await database().connect();
    try {
      await client.query("BEGIN");
      if (storyIds.length) {
        const stories = await client.query("SELECT id FROM mat_stories WHERE id=ANY($1::uuid[]) AND published AND payment_verified FOR SHARE", [storyIds]);
        if (stories.rowCount !== storyIds.length) throw new HttpError(400, "공개된 이야기만 기록할 수 있습니다.");
      }
      for (const e of events) await client.query("INSERT INTO mat_activity_events(id,visit_id,session_id,name,occurred_at,path,story_id,properties) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT DO NOTHING", [e.id,e.visitId,e.sessionId,e.name,e.occurredAt,e.path,e.storyId ?? null,e.properties]);
      await client.query("COMMIT");
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
    return Response.json({ accepted: events.length }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) { return jsonError(error); }
}

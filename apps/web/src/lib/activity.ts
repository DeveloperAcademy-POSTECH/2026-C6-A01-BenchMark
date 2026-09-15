import { z } from "zod";

export const activityNames = ["page_view", "scroll_depth", "active_time", "link_click", "reaction_attempt", "reaction_success", "reaction_failure", "reservation_attempt", "reservation_success", "reservation_failure", "photo_selected"] as const;
export const activityLabels: Record<typeof activityNames[number], string> = {
  page_view: "페이지 조회", scroll_depth: "스크롤 도달", active_time: "활성 체류", link_click: "링크 클릭",
  reaction_attempt: "반응 시도", reaction_success: "반응 성공", reaction_failure: "반응 실패",
  reservation_attempt: "예약 제출 시도", reservation_success: "예약 접수 성공", reservation_failure: "예약 접수 실패", photo_selected: "사진 선택",
};
export const publicPath = z.string().regex(/^\/(?:stories(?:\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})?|reserve)?$/);
const empty = z.object({}).strict();
const reaction = z.object({ kind: z.enum(["like", "empathy", "sad", "cheer"]) }).strict();
const envelopeShape = { id: z.uuid(), visitId: z.uuid(), sessionId: z.uuid(), occurredAt: z.iso.datetime(), path: publicPath, storyId: z.uuid().optional() };
const variants = [
  z.strictObject({ ...envelopeShape, name: z.literal("page_view"), properties: empty }),
  z.strictObject({ ...envelopeShape, name: z.literal("scroll_depth"), properties: z.object({ percent: z.union([z.literal(25), z.literal(50), z.literal(75), z.literal(100)]) }).strict() }),
  z.strictObject({ ...envelopeShape, name: z.literal("active_time"), properties: z.object({ milliseconds: z.number().int().min(1).max(60000) }).strict() }),
  z.strictObject({ ...envelopeShape, name: z.literal("link_click"), properties: z.object({ target: z.enum(["home", "stories", "story", "reserve"]), targetStoryId: z.uuid().optional() }).strict() }),
  ...(["reaction_attempt", "reaction_success", "reaction_failure"] as const).map(name => z.strictObject({ ...envelopeShape, name: z.literal(name), properties: reaction })),
  ...(["reservation_attempt", "reservation_success", "reservation_failure", "photo_selected"] as const).map(name => z.strictObject({ ...envelopeShape, name: z.literal(name), properties: empty })),
] as const;
export const activityEvent = z.discriminatedUnion("name", variants).superRefine((event, ctx) => {
  if (event.path.startsWith("/stories/") && event.storyId !== event.path.slice(9)) ctx.addIssue({ code: "custom", message: "Story and path must match" });
  if (event.name.startsWith("reaction_") && (!event.storyId || event.path === "/reserve" || event.path === "/stories")) ctx.addIssue({ code: "custom", message: "Reaction requires a story page" });
  if ((event.name.startsWith("reservation_") || event.name === "photo_selected") && event.path !== "/reserve") ctx.addIssue({ code: "custom", message: "Reservation requires reservation page" });
});
export type ActivityEvent = z.infer<typeof activityEvent>;
export type ActivityRecord = { id: string; visit_id: string; session_id: string; name: typeof activityNames[number]; occurred_at: string; received_at: string; path: string; story_id: string | null; properties: Record<string, string | number> };
export function csvActivity(rows: ActivityRecord[]) {
  const cell = (value: unknown) => `"${String(value ?? "").replaceAll('"', '""')}"`;
  return "\uFEFF" + [["event_id", "event", "occurred_at_utc", "received_at_utc", "page", "story_id", "session_id", "visit_id", "properties"], ...rows.map(r => [r.id, r.name, r.occurred_at, r.received_at, r.path, r.story_id, r.session_id, r.visit_id, JSON.stringify(r.properties)])].map(row => row.map(cell).join(",")).join("\r\n");
}

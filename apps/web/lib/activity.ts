import { z } from "zod";

export const cameraActivityNames = ["camera_start_attempt", "camera_ready", "camera_failure", "camera_switch", "camera_stop", "camera_retake", "photo_capture_attempt", "photo_capture_success", "photo_capture_failure", "photo_capture_cancelled", "photo_share_attempt", "photo_share_success", "photo_share_failure", "photo_share_cancelled", "photo_share_unavailable", "photo_download_click"] as const;
export const activityNames = ["page_view", "scroll_depth", "active_time", "link_click", "reaction_attempt", "reaction_success", "reaction_failure", "reservation_submit_click", "reservation_reason_opened", "reservation_attempt", "reservation_success", "reservation_failure", "photo_selected", ...cameraActivityNames] as const;
export const activityLabels: Record<typeof activityNames[number], string> = {
  camera_start_attempt: "카메라 시작 시도", camera_ready: "카메라 준비 완료", camera_failure: "카메라 실패", camera_switch: "카메라 전환 시도", camera_stop: "카메라 종료", camera_retake: "다시 촬영 시도", photo_capture_attempt: "사진 촬영 시도", photo_capture_success: "사진 생성 성공", photo_capture_failure: "사진 생성 실패", photo_capture_cancelled: "사진 생성 중단", photo_share_attempt: "사진 공유 시도", photo_share_success: "공유 API 완료", photo_share_failure: "사진 공유 실패", photo_share_cancelled: "사진 공유 취소", photo_share_unavailable: "사진 공유 미지원", photo_download_click: "사진 다운로드 클릭",
  page_view: "페이지 조회", scroll_depth: "스크롤 도달", active_time: "활성 체류", link_click: "링크 클릭",
  reaction_attempt: "반응 시도", reaction_success: "반응 성공", reaction_failure: "반응 실패",
  reservation_submit_click: "예약 접수 버튼 클릭", reservation_reason_opened: "예약 이유 질문 표시", reservation_attempt: "예약 제출 시도", reservation_success: "예약 접수 성공", reservation_failure: "예약 접수 실패", photo_selected: "사진 선택",
};
export const publicPath = z.string().regex(/^\/(?:stories(?:\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})?|reserve|camera)?$/);
const empty = z.object({}).strict();
const reaction = z.object({ kind: z.enum(["like", "empathy", "sad", "cheer"]), action: z.enum(["react", "remove"]).optional() }).strict();
const envelopeShape = { id: z.uuid(), visitId: z.uuid(), sessionId: z.uuid(), occurredAt: z.iso.datetime(), path: publicPath, storyId: z.uuid().optional() };
const variants = [
  z.strictObject({ ...envelopeShape, name: z.literal("page_view"), properties: empty }),
  ...cameraActivityNames.map(name => z.strictObject({ ...envelopeShape, name: z.literal(name), properties: empty })),
  z.strictObject({ ...envelopeShape, name: z.literal("scroll_depth"), properties: z.object({ percent: z.union([z.literal(25), z.literal(50), z.literal(75), z.literal(100)]) }).strict() }),
  z.strictObject({ ...envelopeShape, name: z.literal("active_time"), properties: z.object({ milliseconds: z.number().int().min(1).max(60000) }).strict() }),
  z.strictObject({ ...envelopeShape, name: z.literal("link_click"), properties: z.object({ target: z.enum(["home", "stories", "story", "reserve", "camera"]), targetStoryId: z.uuid().optional() }).strict() }),
  ...(["reaction_attempt", "reaction_success", "reaction_failure"] as const).map(name => z.strictObject({ ...envelopeShape, name: z.literal(name), properties: reaction })),
  ...(["reservation_submit_click", "reservation_reason_opened", "reservation_attempt", "reservation_success", "reservation_failure", "photo_selected"] as const).map(name => z.strictObject({ ...envelopeShape, name: z.literal(name), properties: empty })),
] as const;
export const activityEvent = z.discriminatedUnion("name", variants).superRefine((event, ctx) => {
  if ((cameraActivityNames as readonly string[]).includes(event.name) && event.path !== "/camera") ctx.addIssue({ code: "custom", message: "Camera action requires camera page" });
  if (event.path.startsWith("/stories/") && event.storyId !== event.path.slice(9)) ctx.addIssue({ code: "custom", message: "Story and path must match" });
  if (event.name.startsWith("reaction_") && (!event.storyId || (event.path !== "/" && !event.path.startsWith("/stories/")))) ctx.addIssue({ code: "custom", message: "Reaction requires a story page" });
  if ((event.name.startsWith("reservation_") || event.name === "photo_selected") && event.path !== "/reserve") ctx.addIssue({ code: "custom", message: "Reservation requires reservation page" });
});
export type ActivityEvent = z.infer<typeof activityEvent>;
export type ActivityRecord = { id: string; visit_id: string; session_id: string; name: typeof activityNames[number]; occurred_at: string; received_at: string; path: string; story_id: string | null; properties: Record<string, string | number> };
export function activityKoreaTime(iso: string) {
  return new Date(new Date(iso).getTime() + 9 * 60 * 60 * 1000).toISOString().replace("Z", "+09:00");
}
export function csvActivity(rows: ActivityRecord[]) {
  const cell = (value: unknown) => `"${String(value ?? "").replaceAll('"', '""')}"`;
  return "\uFEFF" + [["event_id", "event", "occurred_at_utc", "received_at_utc", "page", "story_id", "session_id", "visit_id", "properties", "occurred_date_kst", "occurred_at_kst"], ...rows.map(r => [r.id, r.name, r.occurred_at, r.received_at, r.path, r.story_id, r.session_id, r.visit_id, JSON.stringify(r.properties), activityKoreaTime(r.occurred_at).slice(0, 10), activityKoreaTime(r.occurred_at)])].map(row => row.map(cell).join(",")).join("\r\n");
}

import { z } from "zod";
import { database } from "./db";
import { activityNames, publicPath, type ActivityRecord } from "./activity";
import { HttpError } from "./security";

export async function pruneActivity() {
  await database().query("DELETE FROM mat_activity_events WHERE occurred_at <= now() - interval '30 days'");
  await database().query("DELETE FROM mat_rate_limits WHERE key LIKE 'activity:%' AND window_start < now() - interval '1 hour'");
}
const filters = z.object({
  date: z.iso.date().optional(), from: z.iso.datetime().optional(), to: z.iso.datetime().optional(), name: z.enum(activityNames).optional(),
  storyId: z.uuid().optional(), path: publicPath.optional(), cursorTime: z.iso.datetime().optional(), cursorId: z.uuid().optional(),
  format: z.enum(["json", "csv"]).default("json"),
}).strict();
export async function queryActivity(params: URLSearchParams) {
  const parsed = filters.safeParse(Object.fromEntries(params));
  if (!parsed.success) throw new HttpError(400, "조회 조건을 확인해주세요.");
  const f = parsed.data;
  if (!!f.cursorTime !== !!f.cursorId || (f.from && f.to && f.from >= f.to)) throw new HttpError(400, "기간과 다음 페이지 조건을 확인해주세요.");
  if (f.date && (f.from || f.to)) throw new HttpError(400, "일자 또는 시각 범위 중 하나만 선택해주세요.");
  const values: unknown[] = [];
  const conditions = ["occurred_at > now() - interval '30 days'"];
  function where(sql: string, value: unknown) { values.push(value); conditions.push(sql.replace("?", `$${values.length}`)); }
  if (f.date) {
    const start = new Date(`${f.date}T00:00:00+09:00`);
    where("occurred_at >= ?", start.toISOString());
    where("occurred_at < ?", new Date(start.getTime() + 86400000).toISOString());
  }
  if (f.from) where("occurred_at >= ?", f.from);
  if (f.to) where("occurred_at < ?", f.to);
  if (f.name) where("name = ?", f.name);
  if (f.storyId) where("story_id = ?", f.storyId);
  if (f.path) where("path = ?", f.path);
  if (f.cursorTime) { values.push(f.cursorTime, f.cursorId); conditions.push(`(occurred_at,id) < ($${values.length - 1},$${values.length})`); }
  const limit = f.format === "csv" ? 5000 : 100;
  const result = await database().query(`SELECT id,visit_id,session_id,name,occurred_at,received_at,path,story_id,properties FROM mat_activity_events WHERE ${conditions.join(" AND ")} ORDER BY occurred_at DESC,id DESC LIMIT ${limit + 1}`, values);
  if (f.format === "csv" && result.rows.length > limit) throw new HttpError(400, "CSV는 최대 5,000건입니다. 기간 또는 필터를 좁혀주세요.");
  const rows: ActivityRecord[] = result.rows.slice(0, limit).map(r => ({ ...r, occurred_at: r.occurred_at.toISOString(), received_at: r.received_at.toISOString() }));
  const last = rows.at(-1);
  return { rows, next: result.rows.length > limit && last ? { cursorTime: last.occurred_at, cursorId: last.id } : null, format: f.format };
}

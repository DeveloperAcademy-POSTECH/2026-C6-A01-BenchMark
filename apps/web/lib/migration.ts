import { HttpError } from "./security";
import { createHash, timingSafeEqual } from "node:crypto";

export const migrationTables = {
  mat_stories: ["id","mat_number","mat_size","display_name","story","photo","payment_verified","published","revision","created_at","updated_at","title"],
  mat_reservations: ["id","display_name","phone","email","reason","reason_other","title","story","photo","payment_method","amount","source_story_id","story_id","created_at"],
  mat_reactions: ["story_id","device_hash","kind","created_at"],
  mat_activity_events: ["id","visit_id","session_id","name","occurred_at","received_at","path","story_id","properties"],
  mat_rate_limits: ["key","window_start","attempts"],
  schema_migrations: ["name","applied_at"],
} as const;
export type MigrationTable = keyof typeof migrationTables;
export function requireMigration(request: Request) {
  const token = process.env.MIGRATION_TOKEN;
  // Migration access is independent of the Site audience. Keep it disabled
  // outside an explicit import window and never accept visitor identity alone.
  if (process.env.MIGRATION_ENABLED !== "true" || !token || token.length < 32 ||
      request.method !== "GET" && request.method !== "POST") throw new HttpError(404,"Not found");
  const supplied = request.headers.get("x-migration-token") || "";
  if (supplied.length > 256 || !timingSafeEqual(
    createHash("sha256").update(supplied).digest(),
    createHash("sha256").update(token).digest(),
  )) throw new HttpError(404,"Not found");
}
export function migrationTable(value: string | null): MigrationTable {
  if (!value || !(value in migrationTables)) throw new HttpError(400,"Invalid table");
  return value as MigrationTable;
}

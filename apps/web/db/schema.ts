import { sql } from "drizzle-orm";
import { sqliteTable, text, integer, primaryKey, index, uniqueIndex, check } from "drizzle-orm/sqlite-core";

const timestamp = () => sql`(strftime('%Y-%m-%dT%H:%M:%f','now') || '000Z')`;
export const stories = sqliteTable("mat_stories", {
  id: text().primaryKey(), matNumber: integer("mat_number").notNull(), matSize: text("mat_size").notNull(),
  displayName: text("display_name").notNull(), story: text().notNull(), photo: text().notNull(),
  paymentVerified: integer("payment_verified", { mode: "boolean" }).notNull().default(false),
  published: integer({ mode: "boolean" }).notNull().default(false), revision: integer().notNull().default(1),
  createdAt: text("created_at").notNull().default(timestamp()), updatedAt: text("updated_at").notNull().default(timestamp()),
  title: text().notNull().default(""), reservationId: text("reservation_id").unique(), validationGuard: integer("validation_guard"),
}, t => [
  index("mat_stories_mat_order").on(t.matNumber,t.createdAt,t.id),
  check("mat_number_range",sql`${t.matNumber} BETWEEN 1 AND 10000`),
  check("mat_size_values",sql`${t.matSize} IN ('small','large')`),
  check("story_display_name",sql`length(trim(${t.displayName})) BETWEEN 1 AND 40`),
  check("story_title_length",sql`length(${t.title}) <= 80`),
  check("story_photo_key",sql`length(${t.photo}) > 0`),
  check("story_boolean_flags",sql`${t.paymentVerified} IN (0,1) AND ${t.published} IN (0,1)`),
  check("story_bytes",sql`length(cast(trim(${t.story}) as blob)) BETWEEN 1 AND 1000`),
  check("publication_requires_payment",sql`${t.published} = 0 OR ${t.paymentVerified} = 1`),
]);
export const reservations = sqliteTable("mat_reservations", {
  id: text().primaryKey(), displayName: text("display_name").notNull(), phone: text(), email: text(),
  reason: text().notNull(), reasonOther: text("reason_other").notNull().default(""),
  title: text().notNull(), story: text().notNull(), photo: text().notNull(),
  paymentMethod: text("payment_method").notNull(), amount: integer().notNull(),
  sourceStoryId: text("source_story_id").references(() => stories.id,{onDelete:"set null"}),
  storyId: text("story_id").unique().references(() => stories.id,{onDelete:"set null"}),
  createdAt: text("created_at").notNull().default(timestamp()), validationGuard: integer("validation_guard"),
},t=>[
  index("mat_reservations_created").on(t.createdAt),
  check("reservation_reason",sql`${t.reason} IN ('story','rest','project','donate','other')`),
  check("reservation_payment",sql`${t.paymentMethod} IN ('deposit','easy','transfer','other')`),
  check("reservation_amount",sql`${t.amount} > 0 AND ${t.amount} <= 2147483647`),
  check("reservation_display_name",sql`length(trim(${t.displayName})) BETWEEN 1 AND 40`),
  check("reservation_title_length",sql`length(trim(${t.title})) BETWEEN 1 AND 80`),
  check("reservation_reason_other_length",sql`length(${t.reasonOther}) <= 300`),
  check("reservation_email_length",sql`${t.email} IS NULL OR length(${t.email}) BETWEEN 1 AND 254`),
  check("reservation_phone",sql`${t.phone} IS NULL OR (length(${t.phone}) IN (10,11) AND substr(${t.phone},1,2)='01' AND substr(${t.phone},3,1) IN ('0','1','6','7','8','9') AND ${t.phone} NOT GLOB '*[^0-9]*')`),
  check("reservation_photo_key",sql`length(${t.photo}) > 0`),
  check("reservation_story_bytes",sql`length(cast(trim(${t.story}) as blob)) BETWEEN 1 AND 1000`),
  check("reservation_other_reason",sql`${t.reason} <> 'other' OR length(trim(${t.reasonOther})) > 0`),
]);
export const reactions = sqliteTable("mat_reactions", {
  storyId: text("story_id").notNull().references(()=>stories.id,{onDelete:"cascade"}),
  deviceHash: text("device_hash").notNull(), kind: text().notNull().default("empathy"),
  createdAt: text("created_at").notNull().default(timestamp()),
},t=>[primaryKey({columns:[t.storyId,t.deviceHash,t.kind]}),check("reaction_kind",sql`${t.kind} IN ('like','empathy','sad','cheer')`)]);
export const rateLimits = sqliteTable("mat_rate_limits", {
  key: text().primaryKey(), windowStart: text("window_start").notNull(), attempts: integer().notNull(),
});
export const activity = sqliteTable("mat_activity_events", {
  id: text().primaryKey(), visitId: text("visit_id").notNull(), sessionId: text("session_id").notNull(),
  name: text().notNull(), occurredAt: text("occurred_at").notNull(), receivedAt: text("received_at").notNull().default(timestamp()),
  path: text().notNull(), storyId: text("story_id"), properties: text({mode:"json"}).notNull(),
  percent: integer().generatedAlwaysAs(sql`json_extract(properties,'$.percent')`,{mode:"virtual"}), validationGuard: integer("validation_guard"),
},t=>[
  index("mat_activity_period").on(t.occurredAt,t.id), index("mat_activity_received").on(t.receivedAt),
  index("mat_activity_story").on(t.storyId,t.occurredAt), index("mat_activity_name").on(t.name,t.occurredAt),
  uniqueIndex("mat_activity_one_view").on(t.visitId).where(sql`${t.name} = 'page_view'`),
  uniqueIndex("mat_activity_one_depth").on(t.visitId,t.percent).where(sql`${t.name} = 'scroll_depth'`),
  check("activity_properties",sql`json_type(${t.properties}) = 'object' AND length(cast(${t.properties} as blob)) <= 256`),
  check("activity_path_bytes",sql`length(cast(${t.path} as blob)) <= 64`),
  check("activity_names",sql`${t.name} IN ('page_view','scroll_depth','active_time','link_click','reaction_attempt','reaction_success','reaction_failure','reservation_submit_click','reservation_reason_opened','reservation_attempt','reservation_success','reservation_failure','photo_selected','camera_start_attempt','camera_ready','camera_failure','camera_switch','camera_stop','camera_retake','photo_capture_attempt','photo_capture_success','photo_capture_failure','photo_capture_cancelled','photo_share_attempt','photo_share_success','photo_share_failure','photo_share_cancelled','photo_share_unavailable','photo_download_click')`),
]);
export const legacyMigrations = sqliteTable("schema_migrations", {
  name: text().primaryKey(), appliedAt: text("applied_at").notNull(),
});
export const photoJobs = sqliteTable("photo_jobs", {
  id: text().primaryKey(), objectKey: text("object_key").notNull().unique(),
  expiresAt: integer("expires_at").notNull(), consumed: integer().notNull().default(0),
}, t=>[index("photo_jobs_expiry").on(t.expiresAt),check("photo_jobs_consumed",sql`${t.consumed} IN (0,1)`)]);

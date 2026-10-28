PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_mat_activity_events` (
	`id` text PRIMARY KEY NOT NULL,
	`visit_id` text NOT NULL,
	`session_id` text NOT NULL,
	`name` text NOT NULL,
	`occurred_at` text NOT NULL,
	`received_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%f','now') || '000Z') NOT NULL,
	`path` text NOT NULL,
	`story_id` text,
	`properties` text NOT NULL,
	`percent` integer GENERATED ALWAYS AS (json_extract(properties,'$.percent')) VIRTUAL,
	CONSTRAINT "activity_properties" CHECK(json_type("__new_mat_activity_events"."properties") = 'object' AND length(cast("__new_mat_activity_events"."properties" as blob)) <= 256)
);
--> statement-breakpoint
INSERT INTO `__new_mat_activity_events`("id", "visit_id", "session_id", "name", "occurred_at", "received_at", "path", "story_id", "properties") SELECT "id", "visit_id", "session_id", "name", "occurred_at", "received_at", "path", "story_id", "properties" FROM `mat_activity_events`;--> statement-breakpoint
DROP TABLE `mat_activity_events`;--> statement-breakpoint
ALTER TABLE `__new_mat_activity_events` RENAME TO `mat_activity_events`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE INDEX `mat_activity_period` ON `mat_activity_events` (`occurred_at`,`id`);--> statement-breakpoint
CREATE INDEX `mat_activity_received` ON `mat_activity_events` (`received_at`);--> statement-breakpoint
CREATE INDEX `mat_activity_story` ON `mat_activity_events` (`story_id`,`occurred_at`);--> statement-breakpoint
CREATE INDEX `mat_activity_name` ON `mat_activity_events` (`name`,`occurred_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `mat_activity_one_view` ON `mat_activity_events` (`visit_id`) WHERE "mat_activity_events"."name" = 'page_view';--> statement-breakpoint
CREATE UNIQUE INDEX `mat_activity_one_depth` ON `mat_activity_events` (`visit_id`,`percent`) WHERE "mat_activity_events"."name" = 'scroll_depth';--> statement-breakpoint
CREATE TABLE `__new_mat_reactions` (
	`story_id` text NOT NULL,
	`device_hash` text NOT NULL,
	`kind` text DEFAULT 'empathy' NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%f','now') || '000Z') NOT NULL,
	PRIMARY KEY(`story_id`, `device_hash`, `kind`),
	FOREIGN KEY (`story_id`) REFERENCES `mat_stories`(`id`) ON UPDATE no action ON DELETE cascade,
	CONSTRAINT "reaction_kind" CHECK("__new_mat_reactions"."kind" IN ('like','empathy','sad','cheer'))
);
--> statement-breakpoint
INSERT INTO `__new_mat_reactions`("story_id", "device_hash", "kind", "created_at") SELECT "story_id", "device_hash", "kind", "created_at" FROM `mat_reactions`;--> statement-breakpoint
DROP TABLE `mat_reactions`;--> statement-breakpoint
ALTER TABLE `__new_mat_reactions` RENAME TO `mat_reactions`;--> statement-breakpoint
CREATE TABLE `__new_mat_reservations` (
	`id` text PRIMARY KEY NOT NULL,
	`display_name` text NOT NULL,
	`phone` text,
	`email` text,
	`reason` text NOT NULL,
	`reason_other` text DEFAULT '' NOT NULL,
	`title` text NOT NULL,
	`story` text NOT NULL,
	`photo` text NOT NULL,
	`payment_method` text NOT NULL,
	`amount` integer NOT NULL,
	`source_story_id` text,
	`story_id` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%f','now') || '000Z') NOT NULL,
	FOREIGN KEY (`source_story_id`) REFERENCES `mat_stories`(`id`) ON UPDATE no action ON DELETE set null,
	FOREIGN KEY (`story_id`) REFERENCES `mat_stories`(`id`) ON UPDATE no action ON DELETE set null,
	CONSTRAINT "reservation_reason" CHECK("__new_mat_reservations"."reason" IN ('story','rest','project','donate','other')),
	CONSTRAINT "reservation_payment" CHECK("__new_mat_reservations"."payment_method" IN ('deposit','easy','transfer','other')),
	CONSTRAINT "reservation_amount" CHECK("__new_mat_reservations"."amount" > 0 AND "__new_mat_reservations"."amount" <= 2147483647),
	CONSTRAINT "reservation_story_bytes" CHECK(length(cast(trim("__new_mat_reservations"."story") as blob)) BETWEEN 1 AND 1000),
	CONSTRAINT "reservation_other_reason" CHECK("__new_mat_reservations"."reason" <> 'other' OR length(trim("__new_mat_reservations"."reason_other")) > 0)
);
--> statement-breakpoint
INSERT INTO `__new_mat_reservations`("id", "display_name", "phone", "email", "reason", "reason_other", "title", "story", "photo", "payment_method", "amount", "source_story_id", "story_id", "created_at") SELECT "id", "display_name", "phone", "email", "reason", "reason_other", "title", "story", "photo", "payment_method", "amount", "source_story_id", "story_id", "created_at" FROM `mat_reservations`;--> statement-breakpoint
DROP TABLE `mat_reservations`;--> statement-breakpoint
ALTER TABLE `__new_mat_reservations` RENAME TO `mat_reservations`;--> statement-breakpoint
CREATE UNIQUE INDEX `mat_reservations_story_id_unique` ON `mat_reservations` (`story_id`);--> statement-breakpoint
CREATE INDEX `mat_reservations_created` ON `mat_reservations` (`created_at`);--> statement-breakpoint
CREATE TABLE `__new_mat_stories` (
	`id` text PRIMARY KEY NOT NULL,
	`mat_number` integer NOT NULL,
	`mat_size` text NOT NULL,
	`display_name` text NOT NULL,
	`story` text NOT NULL,
	`photo` text NOT NULL,
	`payment_verified` integer DEFAULT false NOT NULL,
	`published` integer DEFAULT false NOT NULL,
	`revision` integer DEFAULT 1 NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%f','now') || '000Z') NOT NULL,
	`updated_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%f','now') || '000Z') NOT NULL,
	`title` text DEFAULT '' NOT NULL,
	`reservation_id` text,
	CONSTRAINT "mat_number_range" CHECK("__new_mat_stories"."mat_number" BETWEEN 1 AND 10000),
	CONSTRAINT "mat_size_values" CHECK("__new_mat_stories"."mat_size" IN ('small','large')),
	CONSTRAINT "story_bytes" CHECK(length(cast(trim("__new_mat_stories"."story") as blob)) BETWEEN 1 AND 1000),
	CONSTRAINT "publication_requires_payment" CHECK("__new_mat_stories"."published" = 0 OR "__new_mat_stories"."payment_verified" = 1)
);
--> statement-breakpoint
INSERT INTO `__new_mat_stories`("id", "mat_number", "mat_size", "display_name", "story", "photo", "payment_verified", "published", "revision", "created_at", "updated_at", "title", "reservation_id") SELECT "id", "mat_number", "mat_size", "display_name", "story", "photo", "payment_verified", "published", "revision", "created_at", "updated_at", "title", "reservation_id" FROM `mat_stories`;--> statement-breakpoint
DROP TABLE `mat_stories`;--> statement-breakpoint
ALTER TABLE `__new_mat_stories` RENAME TO `mat_stories`;--> statement-breakpoint
CREATE UNIQUE INDEX `mat_stories_reservation_id_unique` ON `mat_stories` (`reservation_id`);--> statement-breakpoint
CREATE INDEX `mat_stories_mat_order` ON `mat_stories` (`mat_number`,`created_at`,`id`);

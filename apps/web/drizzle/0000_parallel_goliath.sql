CREATE TABLE `mat_activity_events` (
	`id` text PRIMARY KEY NOT NULL,
	`visit_id` text NOT NULL,
	`session_id` text NOT NULL,
	`name` text NOT NULL,
	`occurred_at` text NOT NULL,
	`received_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')) NOT NULL,
	`path` text NOT NULL,
	`story_id` text,
	`properties` text NOT NULL,
	`percent` integer GENERATED ALWAYS AS (json_extract(properties,'$.percent')) VIRTUAL,
	CONSTRAINT "activity_properties" CHECK(json_type("mat_activity_events"."properties") = 'object' AND length(cast("mat_activity_events"."properties" as blob)) <= 256)
);
--> statement-breakpoint
CREATE INDEX `mat_activity_period` ON `mat_activity_events` (`occurred_at`,`id`);--> statement-breakpoint
CREATE INDEX `mat_activity_received` ON `mat_activity_events` (`received_at`);--> statement-breakpoint
CREATE INDEX `mat_activity_story` ON `mat_activity_events` (`story_id`,`occurred_at`);--> statement-breakpoint
CREATE INDEX `mat_activity_name` ON `mat_activity_events` (`name`,`occurred_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `mat_activity_one_view` ON `mat_activity_events` (`visit_id`) WHERE "mat_activity_events"."name" = 'page_view';--> statement-breakpoint
CREATE UNIQUE INDEX `mat_activity_one_depth` ON `mat_activity_events` (`visit_id`,`percent`) WHERE "mat_activity_events"."name" = 'scroll_depth';--> statement-breakpoint
CREATE TABLE `schema_migrations` (
	`name` text PRIMARY KEY NOT NULL,
	`applied_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `mat_rate_limits` (
	`key` text PRIMARY KEY NOT NULL,
	`window_start` text NOT NULL,
	`attempts` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `mat_reactions` (
	`story_id` text NOT NULL,
	`device_hash` text NOT NULL,
	`kind` text DEFAULT 'empathy' NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')) NOT NULL,
	PRIMARY KEY(`story_id`, `device_hash`, `kind`),
	FOREIGN KEY (`story_id`) REFERENCES `mat_stories`(`id`) ON UPDATE no action ON DELETE cascade,
	CONSTRAINT "reaction_kind" CHECK("mat_reactions"."kind" IN ('like','empathy','sad','cheer'))
);
--> statement-breakpoint
CREATE TABLE `mat_reservations` (
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
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')) NOT NULL,
	FOREIGN KEY (`source_story_id`) REFERENCES `mat_stories`(`id`) ON UPDATE no action ON DELETE set null,
	FOREIGN KEY (`story_id`) REFERENCES `mat_stories`(`id`) ON UPDATE no action ON DELETE set null,
	CONSTRAINT "reservation_reason" CHECK("mat_reservations"."reason" IN ('story','rest','project','donate','other')),
	CONSTRAINT "reservation_payment" CHECK("mat_reservations"."payment_method" IN ('deposit','easy','transfer','other')),
	CONSTRAINT "reservation_amount" CHECK("mat_reservations"."amount" > 0 AND "mat_reservations"."amount" <= 2147483647),
	CONSTRAINT "reservation_story_bytes" CHECK(length(cast(trim("mat_reservations"."story") as blob)) BETWEEN 1 AND 1000),
	CONSTRAINT "reservation_other_reason" CHECK("mat_reservations"."reason" <> 'other' OR length(trim("mat_reservations"."reason_other")) > 0)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `mat_reservations_story_id_unique` ON `mat_reservations` (`story_id`);--> statement-breakpoint
CREATE INDEX `mat_reservations_created` ON `mat_reservations` (`created_at`);--> statement-breakpoint
CREATE TABLE `mat_stories` (
	`id` text PRIMARY KEY NOT NULL,
	`mat_number` integer NOT NULL,
	`mat_size` text NOT NULL,
	`display_name` text NOT NULL,
	`story` text NOT NULL,
	`photo` text NOT NULL,
	`payment_verified` integer DEFAULT false NOT NULL,
	`published` integer DEFAULT false NOT NULL,
	`revision` integer DEFAULT 1 NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')) NOT NULL,
	`updated_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')) NOT NULL,
	`title` text DEFAULT '' NOT NULL,
	`reservation_id` text,
	CONSTRAINT "mat_number_range" CHECK("mat_stories"."mat_number" BETWEEN 1 AND 10000),
	CONSTRAINT "mat_size_values" CHECK("mat_stories"."mat_size" IN ('small','large')),
	CONSTRAINT "story_bytes" CHECK(length(cast(trim("mat_stories"."story") as blob)) BETWEEN 1 AND 1000),
	CONSTRAINT "publication_requires_payment" CHECK("mat_stories"."published" = 0 OR "mat_stories"."payment_verified" = 1)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `mat_stories_reservation_id_unique` ON `mat_stories` (`reservation_id`);--> statement-breakpoint
CREATE INDEX `mat_stories_mat_order` ON `mat_stories` (`mat_number`,`created_at`,`id`);
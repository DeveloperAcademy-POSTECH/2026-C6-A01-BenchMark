CREATE TABLE `photo_jobs` (
	`id` text PRIMARY KEY NOT NULL,
	`object_key` text NOT NULL,
	`expires_at` integer NOT NULL,
	`consumed` integer DEFAULT 0 NOT NULL,
	CONSTRAINT "photo_jobs_consumed" CHECK("photo_jobs"."consumed" IN (0,1))
);
--> statement-breakpoint
CREATE UNIQUE INDEX `photo_jobs_object_key_unique` ON `photo_jobs` (`object_key`);--> statement-breakpoint
CREATE INDEX `photo_jobs_expiry` ON `photo_jobs` (`expires_at`);
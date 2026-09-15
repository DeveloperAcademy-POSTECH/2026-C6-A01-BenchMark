ALTER TABLE mat_stories DROP CONSTRAINT mat_stories_story_bytes_check;
ALTER TABLE mat_stories ADD CONSTRAINT mat_stories_story_bytes_check
  CHECK (octet_length(btrim(story)) BETWEEN 1 AND 1000);

ALTER TABLE mat_reservations DROP CONSTRAINT mat_reservations_story_check;
ALTER TABLE mat_reservations ADD CONSTRAINT mat_reservations_story_check
  CHECK (octet_length(btrim(story)) BETWEEN 1 AND 1000);

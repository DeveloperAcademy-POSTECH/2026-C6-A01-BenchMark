-- A mat may have multiple stories; each existing story UUID remains unchanged.
ALTER TABLE mat_stories DROP CONSTRAINT mat_stories_mat_number_key;
CREATE INDEX mat_stories_mat_order ON mat_stories (mat_number, created_at, id);

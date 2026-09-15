ALTER TABLE mat_stories ADD COLUMN title text NOT NULL DEFAULT '' CHECK (char_length(title) <= 80);
ALTER TABLE mat_stories DROP CONSTRAINT mat_stories_story_check;
ALTER TABLE mat_stories ADD CONSTRAINT mat_stories_story_bytes_check CHECK (octet_length(btrim(story)) BETWEEN 1 AND 500);
ALTER TABLE mat_reactions ADD COLUMN kind text NOT NULL DEFAULT 'empathy' CHECK (kind IN ('like','empathy','sad','cheer'));
ALTER TABLE mat_reactions DROP CONSTRAINT mat_reactions_pkey;
ALTER TABLE mat_reactions ADD PRIMARY KEY (story_id,device_hash,kind);
CREATE TABLE mat_reservations (
  id uuid PRIMARY KEY,
  display_name text NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 40),
  phone text NOT NULL CHECK (phone ~ '^01[016789][0-9]{7,8}$'),
  reason text NOT NULL CHECK (reason IN ('story','rest','project','donate','other')),
  reason_other text NOT NULL DEFAULT '' CHECK (char_length(reason_other) <= 300),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  story text NOT NULL CHECK (octet_length(btrim(story)) BETWEEN 1 AND 500),
  photo bytea NOT NULL CHECK (octet_length(photo) BETWEEN 1 AND 5242880),
  payment_method text NOT NULL CHECK (payment_method IN ('deposit','easy','transfer')),
  amount integer NOT NULL CHECK (amount > 0),
  source_story_id uuid REFERENCES mat_stories(id) ON DELETE SET NULL,
  story_id uuid UNIQUE REFERENCES mat_stories(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (reason <> 'other' OR char_length(btrim(reason_other)) > 0)
);
CREATE INDEX mat_reservations_created ON mat_reservations(created_at DESC);

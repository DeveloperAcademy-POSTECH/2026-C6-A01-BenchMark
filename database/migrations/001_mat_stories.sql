CREATE TABLE mat_stories (
  id uuid PRIMARY KEY,
  mat_number integer NOT NULL UNIQUE CHECK (mat_number BETWEEN 1 AND 10000),
  mat_size text NOT NULL CHECK (mat_size IN ('small', 'large')),
  display_name text NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 40),
  story text NOT NULL CHECK (char_length(btrim(story)) BETWEEN 1 AND 100),
  photo bytea NOT NULL CHECK (octet_length(photo) BETWEEN 1 AND 5242880),
  payment_verified boolean NOT NULL DEFAULT false,
  published boolean NOT NULL DEFAULT false,
  revision integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT published OR payment_verified)
);
CREATE TABLE mat_reactions (
  story_id uuid NOT NULL REFERENCES mat_stories(id) ON DELETE CASCADE,
  device_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, device_hash)
);
CREATE TABLE mat_rate_limits (
  key text PRIMARY KEY,
  window_start timestamptz NOT NULL,
  attempts integer NOT NULL
);
CREATE INDEX mat_public_stories ON mat_stories (mat_number) WHERE published;

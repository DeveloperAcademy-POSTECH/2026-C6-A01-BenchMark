-- Additive: leaves the existing mat pilot and its data untouched.
CREATE TABLE campus_writers (
  id uuid PRIMARY KEY,
  code_hash text NOT NULL UNIQUE,
  code_expires_at timestamptz NOT NULL,
  redeemed_at timestamptz,
  token_hash text UNIQUE,
  token_expires_at timestamptz,
  revoked_at timestamptz,
  approved_by text NOT NULL DEFAULT 'shared-admin',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE campus_ois (
  id uuid PRIMARY KEY,
  writer_id uuid NOT NULL REFERENCES campus_writers(id),
  campus_id text NOT NULL CHECK (campus_id = 'postech'),
  model text NOT NULL CHECK (model = 'helmet-oi'),
  latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  height_meters double precision NOT NULL CHECK (height_meters BETWEEN 0.4 AND 2),
  heading_degrees double precision NOT NULL CHECK (heading_degrees >= 0 AND heading_degrees < 360),
  display_name text NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 40),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  story text NOT NULL CHECK (char_length(btrim(story)) BETWEEN 1 AND 2000),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','published','hidden')),
  revision integer NOT NULL DEFAULT 1,
  request_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX campus_ois_public_location ON campus_ois(latitude,longitude,id) WHERE status='published';
CREATE INDEX campus_ois_writer ON campus_ois(writer_id,id);
CREATE TABLE campus_reviews (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  oi_id uuid NOT NULL,
  action text NOT NULL,
  revision integer NOT NULL,
  actor text NOT NULL DEFAULT 'shared-admin',
  created_at timestamptz NOT NULL DEFAULT now()
);

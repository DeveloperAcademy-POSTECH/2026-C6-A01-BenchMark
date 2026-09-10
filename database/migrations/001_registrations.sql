CREATE TABLE IF NOT EXISTS registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 50),
  phone text NOT NULL UNIQUE CHECK (phone ~ '^010[0-9]{8}$'),
  form_version integer NOT NULL CHECK (form_version > 0),
  answers jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(answers) = 'object'),
  consent_version text NOT NULL,
  consented_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS registrations_expiry_idx ON registrations (expires_at);
CREATE TABLE IF NOT EXISTS registration_rate_limits (
  bucket timestamptz PRIMARY KEY,
  attempts integer NOT NULL CHECK (attempts > 0)
);

-- Preserve existing contacts; only new submissions require email in the API.
ALTER TABLE mat_reservations ALTER COLUMN phone DROP NOT NULL;
ALTER TABLE mat_reservations ADD COLUMN email text CHECK (char_length(email) BETWEEN 1 AND 254);

import type { Pool } from "pg";
import type { Registration } from "./registration";

export async function saveRegistration(pool: Pool, input: Registration, retentionDays: number) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("DELETE FROM registrations WHERE expires_at <= now()");
    await client.query("DELETE FROM registration_rate_limits WHERE bucket < now() - interval '1 hour'");
    const rate = await client.query<{ attempts: number }>(`
      INSERT INTO registration_rate_limits (bucket, attempts) VALUES (date_trunc('minute', now()), 1)
      ON CONFLICT (bucket) DO UPDATE SET attempts = registration_rate_limits.attempts + 1
      RETURNING attempts
    `);
    if (rate.rows[0].attempts > 60) {
      await client.query("COMMIT");
      return "limited" as const;
    }
    // A retry or a repeated phone receives the same response without overwriting its owner.
    await client.query(`
      INSERT INTO registrations (name, phone, form_version, consent_version, expires_at)
      VALUES ($1, $2, $3, $4, now() + make_interval(days => $5))
      ON CONFLICT (phone) DO NOTHING
    `, [input.name, input.phone, input.formVersion, `v1-${retentionDays}d`, retentionDays]);
    await client.query("COMMIT");
    return "accepted" as const;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

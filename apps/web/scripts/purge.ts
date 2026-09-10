import { database } from "../src/lib/db";
const pool = database();
try {
  const result = await pool.query("DELETE FROM registrations WHERE expires_at <= now()");
  await pool.query("DELETE FROM registration_rate_limits WHERE bucket < now() - interval '1 hour'");
  console.info(`Expired registrations removed: ${result.rowCount}`);
} catch {
  console.error("Retention cleanup failed.");
  process.exitCode = 1;
} finally { await pool.end(); }

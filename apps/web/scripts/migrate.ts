import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { database } from "../src/lib/db";
import type { PoolClient } from "pg";

const pool = database();
let client: PoolClient | undefined;
try {
  client = await pool.connect();
  await client.query("BEGIN");
  await client.query("SELECT pg_advisory_xact_lock(20760910)");
  await client.query("CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())");
  const directory = fileURLToPath(new URL("../../../database/migrations/", import.meta.url));
  for (const name of (await readdir(directory)).filter((name) => name.endsWith(".sql")).sort()) {
    const existing = await client.query("SELECT 1 FROM schema_migrations WHERE name = $1", [name]);
    if (existing.rowCount) continue;
    await client.query(await readFile(`${directory}/${name}`, "utf8"));
    await client.query("INSERT INTO schema_migrations (name) VALUES ($1)", [name]);
    console.info(`Applied ${name}`);
  }
  await client.query("COMMIT");
} catch {
  if (client) await client.query("ROLLBACK");
  console.error("Migration failed. Check database connectivity and migration permissions.");
  process.exitCode = 1;
} finally {
  client?.release();
  await pool.end();
}

import { Pool } from "pg";
const globalDatabase = globalThis as typeof globalThis & { benchmarkPool?: Pool };
export function database() {
  if (!process.env.DATABASE_URL) throw new Error("Database is not configured");
  if (!globalDatabase.benchmarkPool) {
    const pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 5, connectionTimeoutMillis: 5000, idleTimeoutMillis: 10000,
      statement_timeout: 5000,
    });
    pool.on("error", () => console.error("Database connection interrupted."));
    globalDatabase.benchmarkPool = pool;
  }
  return globalDatabase.benchmarkPool;
}

import { bindings } from "./sites-storage";

export type Row = Record<string, unknown>;
export type Query = { sql: string; values?: unknown[] };
const now = "(strftime('%Y-%m-%dT%H:%M:%f','now') || '000Z')";

// Repeated positional parameters must be bound in their occurrence order.
export function prepareQuery(query: Query) {
  const values: unknown[] = [];
  const sql = query.sql
    .replace(/::(?:int|uuid)\b/g, "")
    .replace(/\bnow\(\)/g, now)
    .replace(/COALESCE\(bool_or\(([^)]*)\),false\)/g, "COALESCE(max($1),0)")
    .replace(/\$(\d+)/g, (_, index: string) => {
      const value = query.values?.[Number(index) - 1];
      if (value === undefined) throw new Error("Missing SQL parameter");
      const scalar = value instanceof Date ? value.toISOString() : value;
      values.push(typeof scalar === "boolean" ? Number(scalar) : typeof scalar === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(scalar) ? scalar.replace("Z","000Z") : scalar && typeof scalar === "object" ? JSON.stringify(scalar) : scalar);
      return "?";
    });
  return { sql, values };
}

function statement(query: Query) {
  const prepared = prepareQuery(query);
  return bindings().db.prepare(prepared.sql).bind(...prepared.values);
}

function result<T>(value: D1Result<Row>) {
  const rows = value.results.map(row => {
    const restored: Row = { ...row };
    for (const field of ["created_at", "updated_at", "occurred_at", "received_at", "window_start", "applied_at"]) {
      if (typeof restored[field] === "string") restored[field] = new Date(restored[field]);
    }
    for (const field of ["published", "payment_verified", "reacted", "selected"]) {
      if (field in restored) restored[field] = !!restored[field];
    }
    if (typeof restored.properties === "string") restored.properties = JSON.parse(restored.properties);
    return restored as T;
  });
  return { rows, rowCount: value.meta.changes || rows.length };
}

export function database() {
  return {
    async query<T = Row>(sql: string, values: unknown[] = []) {
      const value = await statement({ sql, values }).all<Row>();
      const decoded = result<T>(value);
      if (/^\s*SELECT\b/i.test(sql)) decoded.rowCount = decoded.rows.length;
      return decoded;
    },
    async batch<T = Row>(queries: Query[]) {
      const values = await bindings().db.batch(queries.map(statement));
      return values.map(value => result<T>(value as D1Result<Row>));
    },
  };
}

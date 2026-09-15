import { database } from "./db";
import type { Reservation } from "./reservation";

export async function listReservations(): Promise<Reservation[]> {
  const result = await database().query(`SELECT id,display_name,phone,email,reason,reason_other,title,story,payment_method,amount,source_story_id,story_id,created_at FROM mat_reservations ORDER BY created_at DESC LIMIT 1000`);
  return result.rows.map((r) => ({ ...r, created_at: r.created_at.toISOString() }));
}

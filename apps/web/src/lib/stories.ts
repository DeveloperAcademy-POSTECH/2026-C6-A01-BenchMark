import { database } from "./db";
import type { Story } from "./story";

const publicFields = `s.id, s.mat_number, s.mat_size, s.display_name, s.title, s.story, s.revision,
  (SELECT count(*)::int FROM mat_reactions r WHERE r.story_id=s.id) AS reaction_count`;
export async function listStories(admin = false): Promise<Story[]> {
  const result = await database().query(`SELECT ${publicFields}${admin ? ", s.payment_verified, s.published" : ""}
    FROM mat_stories s ${admin ? "" : "WHERE s.published AND s.payment_verified"} ORDER BY s.mat_number LIMIT 1000`);
  return result.rows;
}
export async function getStory(id: string, admin = false): Promise<Story | undefined> {
  const result = await database().query(`SELECT ${publicFields}${admin ? ", s.payment_verified, s.published" : ""}
    FROM mat_stories s WHERE s.id=$1 ${admin ? "" : "AND s.published AND s.payment_verified"}`, [id]);
  return result.rows[0];
}

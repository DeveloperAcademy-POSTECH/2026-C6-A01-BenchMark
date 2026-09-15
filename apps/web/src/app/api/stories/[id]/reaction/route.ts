import { database } from "@/lib/db";
import { boundedBody, checkOrigin, hash, HttpError, jsonError, rateLimit } from "@/lib/security";
import { uuid, reactionKinds, emptyCounts, type ReactionKind } from "@/lib/story";

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    checkOrigin(request);
    const { id } = await params;
    if (!uuid.safeParse(id).success) throw new HttpError(404, "이야기를 찾을 수 없습니다.");
    let input;
    try { input = JSON.parse((await boundedBody(request, 1024)).toString()); }
    catch (error) { if (error instanceof HttpError) throw error; throw new HttpError(400, "요청을 확인해주세요."); }
    if (!uuid.safeParse(input?.deviceId).success || !["status", "react", "remove"].includes(input?.action)) throw new HttpError(400, "브라우저 정보를 확인해주세요.");
    const kind = input.kind ?? "empathy";
    if (!reactionKinds.includes(kind)) throw new HttpError(400, "반응 종류를 확인해주세요.");
    const deviceHash = hash(input.deviceId);
    if (input.action !== "status") await rateLimit(`reaction:${deviceHash}`, 100, 60);
    const client = await database().connect();
    try {
      await client.query("BEGIN");
      const story = await client.query("SELECT id FROM mat_stories WHERE id=$1 AND published AND payment_verified FOR SHARE", [id]);
      if (!story.rowCount) throw new HttpError(404, "공개된 이야기를 찾을 수 없습니다.");
      await client.query("SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))", [id, deviceHash]);
      if (input.action === "remove") await client.query("DELETE FROM mat_reactions WHERE story_id=$1 AND device_hash=$2 AND kind=$3", [id, deviceHash, kind]);
      if (input.action === "react") await client.query("INSERT INTO mat_reactions(story_id,device_hash,kind) VALUES($1,$2,$3) ON CONFLICT DO NOTHING", [id, deviceHash, kind]);
      const result = await client.query("SELECT count(*)::int AS count,COALESCE(bool_or(device_hash=$2),false) AS reacted FROM mat_reactions WHERE story_id=$1", [id, deviceHash]);
      const grouped = await client.query("SELECT kind,count(*)::int AS count,COALESCE(bool_or(device_hash=$2),false) AS selected FROM mat_reactions WHERE story_id=$1 GROUP BY kind", [id, deviceHash]);
      const counts = emptyCounts(); const selected: ReactionKind[] = [];
      for (const row of grouped.rows) { counts[row.kind as ReactionKind] = row.count; if (row.selected) selected.push(row.kind); }
      await client.query("COMMIT");
      return Response.json({ ...result.rows[0], counts, selected }, { headers: { "Cache-Control": "no-store" } });
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  } catch (error) { return jsonError(error); }
}

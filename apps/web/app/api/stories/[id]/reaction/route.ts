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
    const queries = [];
    if (input.action === "remove") queries.push({sql:"DELETE FROM mat_reactions WHERE story_id=$1 AND device_hash=$2 AND kind=$3 AND EXISTS(SELECT 1 FROM mat_stories WHERE id=$1 AND published AND payment_verified)",values:[id,deviceHash,kind]});
    if (input.action === "react") queries.push({sql:"INSERT INTO mat_reactions(story_id,device_hash,kind) SELECT $1,$2,$3 WHERE EXISTS(SELECT 1 FROM mat_stories WHERE id=$1 AND published AND payment_verified) ON CONFLICT DO NOTHING",values:[id,deviceHash,kind]});
    queries.push({sql:"SELECT id FROM mat_stories WHERE id=$1 AND published AND payment_verified",values:[id]});
    queries.push({sql:"SELECT count(*) AS count,COALESCE(max(device_hash=$2),0) AS reacted FROM mat_reactions WHERE story_id=$1",values:[id,deviceHash]});
    queries.push({sql:"SELECT kind,count(*) AS count,COALESCE(max(device_hash=$2),0) AS selected FROM mat_reactions WHERE story_id=$1 GROUP BY kind",values:[id,deviceHash]});
    const results = await database().batch<{id:string;count:number;reacted:boolean;kind:ReactionKind;selected:boolean}>(queries);
    if (!results.at(-3)?.rowCount) throw new HttpError(404,"공개된 이야기를 찾을 수 없습니다.");
    const counts = emptyCounts(); const selected: ReactionKind[] = [];
    for (const row of results.at(-1)?.rows || []) { counts[row.kind] = row.count; if (row.selected) selected.push(row.kind); }
    return Response.json({ ...results.at(-2)?.rows[0], counts, selected }, {headers:{"Cache-Control":"no-store"}});
  } catch (error) { return jsonError(error); }
}

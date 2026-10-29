import { checkOrigin, jsonError, requireAdmin } from "@/lib/security";
import { saveStory } from "@/lib/save-story";

export async function POST(request: Request) {
  try { checkOrigin(request); await requireAdmin(); return Response.json({ id: await saveStory(request) }, { status: 201 }); }
  catch (error) { return jsonError(error); }
}

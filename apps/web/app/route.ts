import { NextRequest, NextResponse } from "next/server";
import { database } from "@/lib/db";
import { uuid } from "@/lib/story";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const previous = uuid.safeParse(request.cookies.get("last-home-story")?.value);
  const result = await database().query<{ id: string }>(`
    SELECT id FROM mat_stories
    WHERE published AND payment_verified
    ORDER BY (id = $1::uuid) ASC NULLS FIRST, random()
    LIMIT 1
  `, [previous.success ? previous.data : null]);
  const id = result.rows[0]?.id;
  const response = new NextResponse(null, {
    status: 307,
    headers: {
      Location: id ? `/stories/${id}` : "/stories",
      "Cache-Control": "private, no-store, max-age=0",
      Vary: "Cookie",
    },
  });
  if (id) response.cookies.set("last-home-story", id, {
    httpOnly: true, sameSite: "lax", secure: request.nextUrl.protocol === "https:", path: "/",
  });
  return response;
}

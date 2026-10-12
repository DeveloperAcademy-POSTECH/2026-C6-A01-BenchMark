import { NextResponse } from "next/server";
import { authClient } from "@/lib/auth/server";
import { appOrigin, loginDestination } from "@/lib/web-config";

export async function GET(request: Request) {
  const incoming = new URL(request.url);
  const origin = appOrigin();
  if (!origin) return new Response("로그인 주소 설정을 확인해주세요.", { status: 503 });
  const code = incoming.searchParams.get("code");
  const next = loginDestination(incoming.searchParams.get("next"));
  const client = await authClient();
  if (code && !incoming.searchParams.has("error") && client) {
    let failed = true;
    try { const { error } = await client.auth.exchangeCodeForSession(code); failed = !!error; }
    catch { /* Expired or unavailable provider returns to login. */ }
    if (!failed) {
      const response = NextResponse.redirect(new URL(next, origin));
      response.headers.set("Cache-Control", "private, no-store");
      return response;
    }
  }
  const target = new URL("/login", origin);
  target.searchParams.set("error", "callback");
  target.searchParams.set("next", next);
  const response = NextResponse.redirect(target);
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

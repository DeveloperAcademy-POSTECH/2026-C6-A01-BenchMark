import { cookies } from "next/headers";
import { boundedBody, checkOrigin, correctPassword, hash, HttpError, jsonError, makeSession, rateLimit, sessionCookie, rememberAdminBrowser, excludeAdminActivity } from "@/lib/security";

export async function POST(request: Request) {
  try {
    checkOrigin(request);
    const ip = request.headers.get("x-forwarded-for")?.split(",").at(-1)?.trim() || "local";
    await rateLimit("login:global", 100, 900);
    await rateLimit(`login:${hash(ip)}`, 10, 900);
    let input;
    try { input = JSON.parse((await boundedBody(request, 2048)).toString()); } catch (e) { if (e instanceof HttpError) throw e; throw new HttpError(400, "비밀번호를 입력해주세요."); }
    if (typeof input?.password !== "string" || !correctPassword(input.password)) throw new HttpError(401, "비밀번호가 일치하지 않습니다.");
    (await cookies()).set(sessionCookie, makeSession(), { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "strict", path: "/", maxAge: 28800 });
    await rememberAdminBrowser();
    return Response.json({ ok: true });
  } catch (error) { return jsonError(error); }
}
export async function DELETE(request: Request) {
  try { checkOrigin(request); await excludeAdminActivity(); (await cookies()).delete(sessionCookie); return Response.json({ ok: true }); }
  catch (error) { return jsonError(error); }
}

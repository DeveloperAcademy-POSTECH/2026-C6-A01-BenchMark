import { type AppleConfiguration, encryptAppleToken, exchangeAppleCode, isAppleCode } from "../_shared/apple-credentials.ts";

type Config = { url: string; publicKey: string; serviceKey: string; apple?: AppleConfiguration };

function reply(error: string, status: number) {
  return Response.json({ error }, { status, headers: { "Cache-Control": "no-store" } });
}

export function createHandler(config: Config, fetcher: typeof fetch = fetch) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return reply("method_not_allowed", 405);
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer [^\s]+$/i.test(authorization)) return reply("authentication_required", 401);
    if (!config.apple || !config.url || !config.publicKey || !config.serviceKey) return reply("not_configured", 503);
    if (request.headers.get("content-type")?.split(";")[0] !== "application/json") return reply("json_required", 415);
    const signal = AbortSignal.any([request.signal, AbortSignal.timeout(6_000)]);
    const base = config.url.replace(/\/$/, "");
    try {
      const userResponse = await fetcher(`${base}/auth/v1/user`, {
        headers: { apikey: config.publicKey, Authorization: authorization }, signal, redirect: "error",
      });
      if (!userResponse.ok) {
        await userResponse.body?.cancel();
        return reply("authentication_failed", userResponse.status >= 500 ? 503 : 401);
      }
      const user = await userResponse.json();
      const subjects = Array.isArray(user.identities) ? user.identities.flatMap(identity =>
        identity?.provider === "apple" && typeof identity.identity_data?.sub === "string" ? [identity.identity_data.sub] : []) : [];
      if (typeof user.id !== "string" || user.is_anonymous === true || !subjects.length) return reply("apple_identity_required", 403);
      // The gateway imposes its own request size limit. Read at most one small JSON body here.
      const reader = request.body?.getReader();
      if (!reader) return reply("invalid_request", 400);
      let raw = "", bytes = 0;
      const decoder = new TextDecoder();
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) { raw += decoder.decode(); break; }
          bytes += value.byteLength;
          if (bytes > 4096) return reply("request_too_large", 413);
          raw += decoder.decode(value, { stream: true });
        }
      } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
      let input;
      try { input = JSON.parse(raw); } catch { return reply("invalid_request", 400); }
      if (!input || Object.keys(input).length !== 1 || !isAppleCode(input.code)) return reply("invalid_request", 400);
      const credential = await exchangeAppleCode(config.apple, input.code, fetcher, signal);
      if (!subjects.includes(credential.subject)) return reply("apple_identity_mismatch", 403);
      const result = await fetcher(`${base}/rest/v1/rpc/oi_store_apple_token`, {
        method: "POST", signal, redirect: "error",
        headers: { apikey: config.serviceKey, Authorization: `Bearer ${config.serviceKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ p_user: user.id, p_subject: credential.subject,
          p_token: await encryptAppleToken(config.apple, credential.subject, credential.refreshToken) }),
      });
      await result.body?.cancel();
      return result.ok ? new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } }) : reply("token_storage_unavailable", 503);
    } catch { return reply("apple_credentials_unavailable", 503); }
  };
}

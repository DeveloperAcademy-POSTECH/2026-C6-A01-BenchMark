type Configuration = { supabaseUrl: string; publicKey: string; serviceKey: string };
type Proof = { userID: string; sessionID: string; providers: string[] };
class MergeFailure extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) { super(code); this.status = status; this.code = code; }
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
}
async function readJSON(response: Response, limit: number, signal: AbortSignal): Promise<any> {
  const reader = response.body?.getReader();
  if (!reader) throw new MergeFailure(400, "invalid_request");
  const chunks: Uint8Array[] = []; let size = 0;
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener("abort", cancel, { once: true });
  try {
    while (true) {
      if (signal.aborted) throw new MergeFailure(504, "merge_timeout");
      const { done, value } = await reader.read();
      if (signal.aborted) throw new MergeFailure(504, "merge_timeout");
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new MergeFailure(413, "request_too_large");
      chunks.push(value);
    }
  } finally {
    signal.removeEventListener("abort", cancel);
    if (signal.aborted) cancel(); else await reader.cancel();
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder().decode(bytes)); }
  catch { throw new MergeFailure(400, "invalid_request"); }
}
function claims(token: string): any {
  try {
    const parts = token.split("."); if (parts.length !== 3) throw new Error();
    const raw = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(raw + "=".repeat((4 - raw.length % 4) % 4)));
  } catch { throw new MergeFailure(401, "authentication_failed"); }
}

export function createHandler(config: Configuration, fetcher: typeof fetch = fetch, clock: () => number = Date.now) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    if (!config.supabaseUrl || !config.publicKey || !config.serviceKey) return json({ error: "merge_not_configured" }, 503);
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer [^\s]+$/i.test(authorization)) return json({ error: "authentication_required" }, 401);
    if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json") return json({ error: "json_required" }, 415);
    const timeout = AbortSignal.timeout(20_000);
    const signal = AbortSignal.any([timeout, request.signal]);
    const base = config.supabaseUrl.replace(/\/$/, "");
    const now = clock() / 1000;
    try {
      const input = await readJSON(new Response(request.body), 40 * 1024, signal);
      if (!input || typeof input !== "object" || Array.isArray(input) || !["preview", "confirm"].includes(input.action)
        || typeof input.source_access_token !== "string" || !input.source_access_token || input.source_access_token.length > 16 * 1024
        || typeof input.operation_id !== "string" || !uuid.test(input.operation_id)
        || Object.keys(input).some((key) => !["action", "source_access_token", "operation_id", "challenge_id", "consent"].includes(key))) {
        throw new MergeFailure(400, "invalid_merge_request");
      }
      if (input.action === "confirm" && (input.consent !== true || typeof input.challenge_id !== "string" || !uuid.test(input.challenge_id))) {
        throw new MergeFailure(400, "merge_consent_required");
      }
      const verify = async (token: string): Promise<Proof> => {
        // getUser verifies signature and account status. Never trust a client-decoded JWT alone.
        const response = await fetcher(`${base}/auth/v1/user`, { headers: { apikey: config.publicKey, Authorization: `Bearer ${token}` }, signal, redirect: "error" });
        if (!response.ok) { await response.body?.cancel(); throw new MergeFailure(response.status >= 500 ? 503 : 401, "authentication_failed"); }
        const user = await readJSON(response, 64 * 1024, signal);
        const value = claims(token);
        const audience = Array.isArray(value.aud) ? value.aud : [value.aud];
        if (!user || typeof user.id !== "string" || !uuid.test(user.id) || value.sub !== user.id || value.iss !== `${base}/auth/v1`
          || value.role !== "authenticated" || !audience.includes("authenticated") || typeof value.exp !== "number" || value.exp <= now
          || typeof value.session_id !== "string" || !uuid.test(value.session_id)) throw new MergeFailure(401, "authentication_failed");
        // Refreshing an old session updates iat, but does not constitute a new OAuth proof.
        if (!Array.isArray(value.amr) || !value.amr.some((entry: any) => entry?.method === "oauth" && typeof entry.timestamp === "number"
          && entry.timestamp >= now - 600 && entry.timestamp <= now + 30)) throw new MergeFailure(401, "recent_login_required");
        const providers = Array.isArray(user.identities) ? user.identities.map((identity: any) => identity?.provider).filter((provider: any) => provider === "google" || provider === "apple") : [];
        if (!providers.length) throw new MergeFailure(403, "google_or_apple_required");
        return { userID: user.id.toLowerCase(), sessionID: value.session_id.toLowerCase(), providers };
      };
      const target = await verify(authorization.replace(/^Bearer /i, ""));
      const source = await verify(input.source_access_token);
      if (target.userID === source.userID) throw new MergeFailure(409, "accounts_already_unified");
      if (!((target.providers.includes("google") && source.providers.includes("apple"))
        || (target.providers.includes("apple") && source.providers.includes("google")))) throw new MergeFailure(403, "both_providers_required");
      const response = await fetcher(`${base}/rest/v1/rpc/oi_merge_accounts`, { method: "POST", signal, redirect: "error",
        headers: { apikey: config.serviceKey, Authorization: `Bearer ${config.serviceKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ p_action: input.action, p_operation_id: input.operation_id, p_target_user_id: target.userID,
          p_source_user_id: source.userID, p_target_session_id: target.sessionID, p_source_session_id: source.sessionID,
          p_challenge_id: input.action === "confirm" ? input.challenge_id : null, p_consent: input.action === "confirm" && input.consent === true }) });
      let result: any;
      try { result = await readJSON(response, 16 * 1024, signal); }
      catch { throw new MergeFailure(503, "merge_unavailable"); }
      if (!response.ok) {
        const allowed = new Set(["merge_challenge_expired", "merge_operation_conflict", "merge_challenge_invalid", "merge_account_changed",
          "operator_accounts_cannot_merge", "accounts_already_unified", "recent_login_required", "merge_consent_required", "merge_rate_limited"]);
        const code = allowed.has(result?.message) ? result.message : "merge_unavailable";
        const status = result?.code === "53300" ? 429 : result?.code === "40001" ? 409 : result?.code === "42501" ? 403 : result?.code === "22023" ? 400 : 503;
        throw new MergeFailure(status, code);
      }
      if (input.action === "preview") {
        const counts = result?.counts;
        const countKeys = ["stories", "collections", "favorites", "evidence", "grants"];
        if (!result || typeof result.challenge_id !== "string" || !uuid.test(result.challenge_id)
          || typeof result.target_account_id !== "string" || !uuid.test(result.target_account_id)
          || typeof result.source_account_id !== "string" || !uuid.test(result.source_account_id)
          || typeof result.source_is_new !== "boolean" || typeof result.expires_at !== "string" || !Number.isFinite(Date.parse(result.expires_at))
          || !counts || countKeys.some((key) => !Number.isSafeInteger(counts[key]) || counts[key] < 0)) {
          throw new MergeFailure(503, "merge_unavailable");
        }
        return json({ challenge_id: result.challenge_id, target_account_id: result.target_account_id, source_account_id: result.source_account_id,
          source_is_new: result.source_is_new, expires_at: result.expires_at, counts: Object.fromEntries(countKeys.map((key) => [key, counts[key]])) });
      }
      if (!result || typeof result.account_id !== "string" || !uuid.test(result.account_id) || typeof result.already_merged !== "boolean") {
        throw new MergeFailure(503, "merge_unavailable");
      }
      return json({ account_id: result.account_id, already_merged: result.already_merged });
    } catch (error) {
      if (signal.aborted) return json({ error: "merge_timeout" }, 504);
      if (error instanceof MergeFailure) return json({ error: error.code }, error.status);
      return json({ error: "merge_unavailable" }, 503);
    }
  };
}

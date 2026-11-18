import { AnalysisError, readBounded } from "../_shared/document-analysis.ts";

type Configuration = { supabaseUrl: string; anonKey: string; serviceKey: string };
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const json = (value: unknown, status = 200) => Response.json(value,
  { status, headers: { "Cache-Control": "no-store" } });

export function createShowcasePublicationHandler(config: Configuration,
  verifyTransaction: (jws: string) => Promise<void>, fetcher: typeof fetch = fetch) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const authorization = request.headers.get("authorization") ?? "";
    const bearer = authorization.match(/^Bearer ([^\s]+)$/i);
    if (!bearer) return json({ error: "authentication_required" }, 401);
    if (!config.supabaseUrl || !config.anonKey || !config.serviceKey) return json({ error: "publication_unavailable" }, 503);
    const signal = AbortSignal.any([request.signal, AbortSignal.timeout(25_000)]);
    async function api(path: string, headers: Record<string, string>, body?: unknown) {
      const response = await fetcher(new URL(path, config.supabaseUrl), {
        method: body === undefined ? "GET" : "POST", headers, signal, redirect: "error",
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new AnalysisError([400, 401, 402, 403, 409, 422, 429, 503].includes(response.status) ? response.status : 502,
          response.status === 402 ? "pickle_coins_insufficient" : "publication_unavailable");
      }
      return JSON.parse(new TextDecoder().decode(await readBounded(response, 64 * 1024, signal)));
    }
    try {
      // Verify the exact access token before reading claims. The RPC checks the persisted session too.
      const user = await api("/auth/v1/user", { apikey: config.anonKey, Authorization: authorization });
      let claims;
      try { claims = JSON.parse(atob(bearer[1].split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))); }
      catch { throw new AnalysisError(401, "authentication_failed"); }
      if (!uuid.test(user.id) || user.is_anonymous === true || claims.sub !== user.id ||
        claims.role !== "authenticated" || typeof claims.session_id !== "string" || !uuid.test(claims.session_id)) {
        throw new AnalysisError(401, "authentication_failed");
      }
      let body;
      try { body = JSON.parse(new TextDecoder().decode(await readBounded(new Response(request.body), 32 * 1024, signal))); }
      catch { throw new AnalysisError(400, "invalid_submission"); }
      const submission = body?.submission;
      if (!submission || typeof submission.id !== "string" || !uuid.test(submission.id) ||
        !Number.isSafeInteger(submission.revision) || submission.revision < 1 || submission.scope !== undefined ||
        typeof body.app_transaction !== "string" || body.app_transaction.length < 1 || body.app_transaction.length > 24 * 1024) {
        throw new AnalysisError(400, "invalid_submission");
      }
      try { await verifyTransaction(body.app_transaction); }
      catch { throw new AnalysisError(403, "testflight_required"); }
      const story = await api("/rest/v1/rpc/oi_publish_showcase_story", {
        apikey: config.serviceKey, Authorization: `Bearer ${config.serviceKey}`, "Content-Type": "application/json",
      }, { p_user: user.id, p_session: claims.session_id, p_submission: submission });
      return json(story);
    } catch (error) {
      if (error instanceof AnalysisError) return json({ error: error.message }, error.status);
      return json({ error: "publication_unavailable" }, signal.aborted ? 503 : 502);
    }
  };
}

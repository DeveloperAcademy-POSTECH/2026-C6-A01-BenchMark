import {
  AnalysisError, analyzeDocument, DEFAULT_MODEL, MAX_FILE_BYTES, readBounded, SCHOOL_PROMPT_VERSION,
} from "../_shared/document-analysis.ts";

type Configuration = {
  enabled: boolean; supabaseUrl: string; supabaseKey: string; openaiKey: string; model?: string;
};

function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
}

export function createSchoolHandler(config: Configuration, fetcher: typeof fetch = fetch) {
  // Per-isolate limits; production still requires a distributed quota.
  const attempts = new Map<string, { count: number; expires: number }>();
  let active = 0;
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer [^\s]+$/i.test(authorization)) return json({ error: "authentication_required" }, 401);
    if (!config.enabled || !config.supabaseUrl || !config.supabaseKey || !config.openaiKey.trim()) {
      return json({ error: "analysis_not_configured" }, 503);
    }
    const signal = AbortSignal.any([AbortSignal.timeout(60_000), request.signal]);
    let locked = false;
    try {
      const call = async (path: string, init: RequestInit = {}) => {
        const response = await fetcher(new URL(path, config.supabaseUrl), {
          ...init, signal, redirect: "error",
          headers: { apikey: config.supabaseKey, Authorization: authorization, "Content-Type": "application/json" },
        });
        if (!response.ok) {
          await response.body?.cancel();
          if (response.status === 401) throw new AnalysisError(401, "authentication_failed");
          throw new AnalysisError(503, "authorization_unavailable");
        }
        return JSON.parse(new TextDecoder().decode(await readBounded(response, 32 * 1024, signal)));
      };
      const user = await call("/auth/v1/user");
      if (typeof user?.id !== "string" || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(user.id)) {
        throw new AnalysisError(401, "authentication_failed");
      }
      const requireOperator = async () => {
        const capabilities = await call("/rest/v1/rpc/oi_capabilities", { method: "POST", body: "{}" });
        if (capabilities?.operator !== true) throw new AnalysisError(403, "operator_required");
      };
      await requireOperator();
      const contentType = request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() ?? "";
      if (!["image/jpeg", "image/png", "application/pdf"].includes(contentType)) {
        throw new AnalysisError(415, "unsupported_document");
      }
      if (active >= 3) throw new AnalysisError(429, "analysis_busy");
      const now = Date.now();
      for (const [actor, entry] of attempts) if (entry.expires <= now) attempts.delete(actor);
      const entry = attempts.get(user.id) ?? { count: 0, expires: now + 60_000 };
      if (entry.count >= 5 || (!attempts.has(user.id) && attempts.size >= 1000)) {
        throw new AnalysisError(429, "analysis_rate_limited");
      }
      entry.count += 1;
      attempts.set(user.id, entry);
      active += 1;
      locked = true;

      const length = request.headers.get("content-length");
      const bytes = await readBounded(new Response(request.body, {
        headers: length === null ? undefined : { "content-length": length },
      }), MAX_FILE_BYTES, signal);
      const assessment = await analyzeDocument({
        bytes, contentType, apiKey: config.openaiKey, model: config.model,
        signal, fetcher, review: "school_affiliation",
      });
      await requireOperator();
      signal.throwIfAborted();
      return json({
        review_type: "school_affiliation",
        analyzed_at: new Date().toISOString(),
        model: config.model ?? DEFAULT_MODEL,
        prompt_version: SCHOOL_PROMPT_VERSION,
        human_review_required: true,
        authenticity_verified: false,
        affiliation_verified: false,
        notice: "AI 참고 분석입니다. 학교 소속이나 발급 사실을 확인하지 않으며 운영자 검토가 필요합니다.",
        assessment,
      });
    } catch (error) {
      if (signal.aborted) return json({ error: "analysis_timeout" }, 504);
      if (error instanceof AnalysisError) return json({ error: error.code }, error.status);
      return json({ error: "analysis_unavailable" }, 503);
    } finally {
      if (locked) active -= 1;
    }
  };
}

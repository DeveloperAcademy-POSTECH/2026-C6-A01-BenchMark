import { AnalysisError, MAX_FILE_BYTES, readBounded } from "../_shared/document-analysis.ts";
import { analyzeCertificate, certificateDecision, certificateDigests, CERTIFICATE_PROMPT_VERSION } from "./certificate-assessment.ts";

type Configuration = {
  supabaseUrl: string; supabaseKey: string; serviceKey: string; openaiKey: string; model?: string;
};
type Evidence = {
  id: string; user_id: string; storage_owner_id: string; status: string;
  object_path: string; submitted_at: string; coin_verification: boolean; coin_consent_version: number;
  review_note?: string | null;
};
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const hex = /^[0-9a-f]{64}$/;
const notice = "AI는 제출 자료의 기부 완료 근거를 확인해요. 발급기관의 공식 확인이나 실제 납입·진위·제출자 본인 여부를 보증하지 않아요.";

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
}

export function createDonationHandler(config: Configuration, fetcher: typeof fetch = fetch) {
  // SQL also serializes settlement; these limits only bound work in this isolate.
  const attempts = new Map<string, { count: number; expires: number }>();
  const active = new Set<string>();
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const authorization = request.headers.get("authorization") ?? "";
    const bearer = authorization.match(/^Bearer ([^\s]+)$/i);
    if (!bearer) return json({ error: "authentication_required" }, 401);
    const token = bearer[1];
    if (!config.supabaseUrl || !config.supabaseKey || !config.serviceKey.trim() || !config.openaiKey.trim()) {
      return json({ error: "analysis_not_configured" }, 503);
    }
    const signal = AbortSignal.any([request.signal, AbortSignal.timeout(55_000)]);
    const userHeaders = { apikey: config.supabaseKey, Authorization: authorization, "Content-Type": "application/json" };
    const serviceHeaders = { apikey: config.serviceKey, Authorization: `Bearer ${config.serviceKey}`, "Content-Type": "application/json" };
    let lockedId: string | undefined;

    async function call(path: string, code: string, body?: unknown, service = false) {
      const response = await fetcher(new URL(path, config.supabaseUrl), {
        method: body === undefined ? "GET" : "POST", headers: service ? serviceHeaders : userHeaders,
        body: body === undefined ? undefined : JSON.stringify(body), signal, redirect: "error",
      });
      if (!response.ok) {
        await response.body?.cancel();
        const status = [400, 401, 403, 404, 409, 422, 429].includes(response.status) ? response.status : 503;
        throw new AnalysisError(status, code === "analysis_busy" && status === 429 ? "analysis_rate_limited" : code);
      }
      return JSON.parse(new TextDecoder().decode(await readBounded(response, 64 * 1024, signal)));
    }
    async function verifiedSession() {
      const user = await call("/auth/v1/user", "authentication_failed");
      // Auth validates this exact token before its session claim is used by the service-only RPC.
      try {
        const claims = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
        if (object(user) && typeof user.id === "string" && uuid.test(user.id) && user.is_anonymous !== true &&
          claims.sub === user.id && claims.role === "authenticated" && typeof claims.session_id === "string" && uuid.test(claims.session_id)) {
          return { p_user: user.id, p_session: claims.session_id };
        }
      } catch { /* Invalid claims use the same authentication error. */ }
      throw new AnalysisError(401, "authentication_failed");
    }
    async function accountId(user: string): Promise<string> {
      const context = await call("/rest/v1/rpc/oi_account_context", "authorization_unavailable", {});
      if (!object(context) || typeof context.id !== "string" || !uuid.test(context.id) || context.auth_user_id !== user) {
        throw new AnalysisError(401, "authentication_failed");
      }
      return context.id;
    }

    try {
      const identity = await verifiedSession();
      if (request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "application/json") {
        throw new AnalysisError(415, "json_required");
      }
      let input: unknown;
      try {
        input = JSON.parse(new TextDecoder().decode(await readBounded(new Response(request.body), 1024, signal)));
      } catch (error) {
        if (error instanceof AnalysisError || signal.aborted) throw error;
        throw new AnalysisError(400, "invalid_request");
      }
      if (!object(input) || Object.keys(input).length !== 1 || typeof input.evidence_id !== "string" || !uuid.test(input.evidence_id)) {
        throw new AnalysisError(400, "invalid_request");
      }
      const id = input.evidence_id.toLowerCase();
      const owner = await accountId(identity.p_user);
      const loadEvidence = async (): Promise<Evidence> => {
        const rows = await call(`/rest/v1/oi_evidence_requests?id=eq.${id}&select=*&limit=1`, "evidence_unavailable");
        if (!Array.isArray(rows) || rows.length !== 1 || !object(rows[0]) || rows[0].user_id !== owner) {
          throw new AnalysisError(404, "evidence_not_found");
        }
        const row = rows[0];
        if (row.coin_verification !== true || row.coin_consent_version !== 1) {
          throw new AnalysisError(409, "coin_evidence_consent_required");
        }
        if (row.id !== id || typeof row.storage_owner_id !== "string" || !uuid.test(row.storage_owner_id) ||
          typeof row.object_path !== "string" || typeof row.submitted_at !== "string" || !Number.isFinite(Date.parse(row.submitted_at))) {
          throw new AnalysisError(409, "invalid_evidence_reference");
        }
        const parts = row.object_path.split("/");
        if (parts.length !== 3 || parts[0] !== row.storage_owner_id || parts[1] !== id ||
          ["", ".", ".."].includes(parts[2]) || /[\\\x00-\x1f\x7f]/.test(row.object_path)) {
          throw new AnalysisError(409, "invalid_evidence_reference");
        }
        return row as Evidence;
      };
      const evidence = await loadEvidence();
      if (["approved", "rejected", "changes_requested"].includes(evidence.status)) {
        const wallet = await call("/rest/v1/rpc/oi_pickle_wallet", "wallet_unavailable", {});
        return json({ request: evidence, wallet, duplicate: evidence.review_note === "duplicate_certificate", credited: false,
          review_type: "pickle_coin_certificate", prompt_version: CERTIFICATE_PROMPT_VERSION,
          authenticity_verified: false, holder_verified: false, notice });
      }
      if (evidence.status !== "pending") throw new AnalysisError(409, "evidence_not_pending");
      if (active.has(id) || active.size >= 3) throw new AnalysisError(429, "analysis_busy");
      const now = Date.now();
      for (const [actor, entry] of attempts) if (entry.expires <= now) attempts.delete(actor);
      const entry = attempts.get(owner) ?? { count: 0, expires: now + 60_000 };
      if (entry.count >= 5 || (!attempts.has(owner) && attempts.size >= 1000)) {
        throw new AnalysisError(429, "analysis_rate_limited");
      }
      attempts.set(owner, { count: entry.count + 1, expires: entry.expires });
      active.add(id);
      lockedId = id;

      const prepared = await call("/rest/v1/rpc/oi_prepare_coin_evidence", "analysis_busy", { ...identity, p_request: id }, true);
      if (!object(prepared) || prepared.id !== id || prepared.user_id !== owner || prepared.status !== "pending" ||
        prepared.object_path !== evidence.object_path || prepared.submitted_at !== evidence.submitted_at ||
        prepared.coin_verification !== true || prepared.coin_consent_version !== 1) {
        throw new AnalysisError(409, "evidence_changed");
      }

      const file = await fetcher(new URL(`/storage/v1/object/authenticated/oi-evidence/${evidence.object_path.split("/").map(encodeURIComponent).join("/")}`, config.supabaseUrl), {
        headers: userHeaders, signal, redirect: "error",
      });
      if (!file.ok) {
        await file.body?.cancel();
        throw new AnalysisError(503, "evidence_download_failed");
      }
      const bytes = await readBounded(file, MAX_FILE_BYTES, signal);
      const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), byte => byte.toString(16).padStart(2, "0")).join("");
      const facts = await analyzeCertificate({ bytes, contentType: file.headers.get("content-type") ?? "",
        apiKey: config.openaiKey, model: config.model, signal, fetcher });
      const currentIdentity = await verifiedSession();
      if (currentIdentity.p_user !== identity.p_user || currentIdentity.p_session !== identity.p_session) {
        throw new AnalysisError(401, "authentication_failed");
      }
      if (await accountId(identity.p_user) !== owner) throw new AnalysisError(409, "account_changed");
      const current = await loadEvidence();
      if (current.status !== "pending" || current.object_path !== evidence.object_path || current.submitted_at !== evidence.submitted_at) {
        throw new AnalysisError(409, "evidence_changed");
      }
      const key = await call("/rest/v1/rpc/oi_evidence_fingerprint_key", "duplicate_check_unavailable", {}, true);
      if (typeof key !== "string" || !hex.test(key)) throw new AnalysisError(503, "duplicate_check_unavailable");
      const digests = await certificateDigests(facts, key);
      const decision = certificateDecision(facts);
      signal.throwIfAborted();
      const result = await call("/rest/v1/rpc/oi_coin_evidence_review", "evidence_settlement_unavailable", {
        ...identity, p_request: id, p_object_path: evidence.object_path, p_submitted_at: evidence.submitted_at,
        p_sha256: sha256, p_semantic_digest: digests.semantic, p_secondary_digest: digests.reference,
        p_decision: decision.decision, p_reason: decision.reason,
      }, true);
      if (!object(result) || !object(result.request) || result.request.id !== id || result.request.user_id !== owner ||
        !object(result.wallet) || typeof result.duplicate !== "boolean" || typeof result.credited !== "boolean") {
        throw new AnalysisError(503, "invalid_settlement_response");
      }
      return json({ ...result, review_type: "pickle_coin_certificate", prompt_version: CERTIFICATE_PROMPT_VERSION,
        authenticity_verified: false, holder_verified: false, notice });
    } catch (error) {
      if (signal.aborted) return json({ error: request.signal.aborted ? "analysis_cancelled" : "analysis_timeout" }, request.signal.aborted ? 499 : 504);
      if (error instanceof AnalysisError) {
        const response = json({ error: error.code }, error.status);
        if (error.code === "analysis_busy" && error.status === 409) response.headers.set("Retry-After", "120");
        if (error.code === "analysis_rate_limited") response.headers.set("Retry-After", "60");
        return response;
      }
      return json({ error: "analysis_unavailable" }, 503);
    } finally {
      if (lockedId) active.delete(lockedId);
    }
  };
}

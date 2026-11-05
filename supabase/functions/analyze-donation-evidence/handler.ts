import { AnalysisError, DEFAULT_MODEL, MAX_FILE_BYTES, readBounded } from "../_shared/document-analysis.ts";
import { analyzeDonationDocument, assessDonation, DONATION_PROMPT_VERSION, semanticDigest, semanticReference } from "./donation-assessment.ts";
import type { DuplicateCheck } from "./donation-assessment.ts";

type Configuration = {
  supabaseUrl: string; supabaseKey: string; serviceKey: string; openaiKey: string; model?: string;
};
type Evidence = { id: string; user_id: string; storage_owner_id?: string; status: string; object_path: string; submitted_at: string };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
}

export function createDonationHandler(config: Configuration, fetcher: typeof fetch = fetch) {
  // Best-effort per-isolate protection, not a distributed billing quota.
  const attempts = new Map<string, { count: number; expires: number }>();
  const active = new Set<string>();
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const authorization = request.headers.get("authorization") ?? "";
    if (!/^Bearer [^\s]+$/i.test(authorization)) return json({ error: "authentication_required" }, 401);
    if (!config.supabaseUrl || !config.supabaseKey || !config.serviceKey?.trim() || !config.openaiKey.trim()) {
      return json({ error: "analysis_not_configured" }, 503);
    }
    const timeout = AbortSignal.timeout(60_000);
    const signal = AbortSignal.any([timeout, request.signal]);
    let lockedId: string | undefined;
    try {
      const headers = { apikey: config.supabaseKey, Authorization: authorization, "Content-Type": "application/json" };
      const call = (path: string, init: RequestInit = {}) => fetcher(`${config.supabaseUrl.replace(/\/$/, "")}${path}`, {
        ...init, headers, signal, redirect: "error",
      });
      const readJSON = async (response: Response, code: string) => {
        if (!response.ok) {
          await response.body?.cancel();
          throw new AnalysisError(response.status === 401 ? 401 : 503, code);
        }
        return JSON.parse(new TextDecoder().decode(await readBounded(response, 32 * 1024, signal)));
      };
      const user = await readJSON(await call("/auth/v1/user"), "authentication_failed");
      if (typeof user?.id !== "string" || !uuid.test(user.id)) throw new AnalysisError(401, "authentication_failed");
      if (user.is_anonymous === true) throw new AnalysisError(401, "authentication_failed");
      const accountContext = async () => {
        const context = await readJSON(await call("/rest/v1/rpc/oi_account_context", { method: "POST", body: "{}" }), "authorization_unavailable");
        if (typeof context?.id !== "string" || !uuid.test(context.id) || context.auth_user_id !== user.id) {
          throw new AnalysisError(401, "authentication_failed");
        }
        return context.id as string;
      };
      const owner = await accountContext();
      if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json") {
        throw new AnalysisError(415, "json_required");
      }
      let input: unknown;
      try {
        input = JSON.parse(new TextDecoder().decode(await readBounded(new Response(request.body), 1024, signal)));
      } catch (error) {
        if (error instanceof AnalysisError) throw error;
        throw new AnalysisError(400, "invalid_request");
      }
      if (typeof input !== "object" || input === null || Array.isArray(input)
        || Object.keys(input).length !== 1 || !("evidence_id" in input)
        || typeof input.evidence_id !== "string" || !uuid.test(input.evidence_id)) {
        throw new AnalysisError(400, "invalid_request");
      }
      const id = input.evidence_id.toLowerCase();
      if (active.has(id) || active.size >= 3) throw new AnalysisError(429, "analysis_busy");
      const now = Date.now();
      for (const [actor, entry] of attempts) if (entry.expires <= now) attempts.delete(actor);
      const entry = attempts.get(owner) ?? { count: 0, expires: now + 60_000 };
      if (entry.count >= 5 || (!attempts.has(owner) && attempts.size >= 1000)) {
        throw new AnalysisError(429, "analysis_rate_limited");
      }
      entry.count += 1;
      attempts.set(owner, entry);
      active.add(id);
      lockedId = id;
      const loadEvidence = async (): Promise<Evidence> => {
        const rows = await readJSON(await call(`/rest/v1/oi_evidence_requests?id=eq.${id}&select=id,user_id,storage_owner_id,status,object_path,submitted_at&limit=1`), "evidence_unavailable");
        if (!Array.isArray(rows) || rows.length !== 1) throw new AnalysisError(404, "evidence_not_found");
        const row = rows[0];
        if (row.status !== "pending" || typeof row.object_path !== "string" || !row.submitted_at) {
          throw new AnalysisError(409, "evidence_not_pending");
        }
        if (row.user_id !== owner) throw new AnalysisError(404, "evidence_not_found");
        const storageOwner = row.storage_owner_id ?? row.user_id;
        if (row.id !== id || typeof row.user_id !== "string" || !uuid.test(row.user_id)
          || typeof storageOwner !== "string" || !uuid.test(storageOwner)
          || !row.object_path.startsWith(`${storageOwner}/${id}/`)
          || row.object_path.split("/").length !== 3 || /[\\\x00-\x1f]/.test(row.object_path)
          || [".", "..", ""].includes(row.object_path.split("/")[2])) {
          throw new AnalysisError(409, "invalid_evidence_reference");
        }
        return row;
      };
      const evidence = await loadEvidence();
      const file = await call(`/storage/v1/object/authenticated/oi-evidence/${evidence.object_path.split("/").map(encodeURIComponent).join("/")}`);
      if (!file.ok) {
        await file.body?.cancel();
        throw new AnalysisError(503, "evidence_download_failed");
      }
      const bytes = await readBounded(file, MAX_FILE_BYTES, signal);
      const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)))
        .map((value) => value.toString(16).padStart(2, "0")).join("");
      const facts = await analyzeDonationDocument({ bytes, contentType: file.headers.get("content-type") ?? "",
        apiKey: config.openaiKey, model: config.model, signal, fetcher });
      const currentUser = await readJSON(await call("/auth/v1/user"), "authentication_failed");
      if (currentUser?.id !== user.id || currentUser.is_anonymous === true) {
        throw new AnalysisError(401, "authentication_failed");
      }
      if (await accountContext() !== owner) throw new AnalysisError(409, "account_changed");
      const current = await loadEvidence();
      if (current.object_path !== evidence.object_path || current.submitted_at !== evidence.submitted_at) {
        throw new AnalysisError(409, "evidence_changed");
      }
      // Only trusted server credentials can register hashes; never expose the ledger to submitters.
      // The RPC rechecks ownership/version and serializes concurrent duplicate registration.
      const serverHeaders = { apikey: config.serviceKey, Authorization: `Bearer ${config.serviceKey}`, "Content-Type": "application/json" };
      let referenceDigest: string | null = null;
      if (semanticReference(facts)) {
        const keyResponse = await fetcher(`${config.supabaseUrl.replace(/\/$/, "")}/rest/v1/rpc/oi_evidence_fingerprint_key`, {
          method: "POST", body: "{}", signal, redirect: "error", headers: serverHeaders,
        });
        const key = await readJSON(keyResponse, "duplicate_check_unavailable");
        if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key)) throw new AnalysisError(503, "duplicate_check_unavailable");
        referenceDigest = await semanticDigest(facts, key);
      }
      const registration = await fetcher(`${config.supabaseUrl.replace(/\/$/, "")}/rest/v1/rpc/oi_register_evidence_fingerprint`, {
        method: "POST", signal, redirect: "error",
        headers: serverHeaders,
        body: JSON.stringify({ p_evidence_id: id, p_user_id: owner, p_object_path: evidence.object_path,
          p_submitted_at: evidence.submitted_at, p_sha256: digest, p_semantic_digest: referenceDigest }),
      });
      if (!registration.ok) {
        const status = registration.status;
        await registration.body?.cancel();
        throw new AnalysisError(status === 409 ? 409 : 503, status === 409 ? "evidence_changed" : "duplicate_check_unavailable");
      }
      const duplicate: DuplicateCheck = await readJSON(registration, "duplicate_check_unavailable");
      if (!duplicate || typeof duplicate.exact_duplicate !== "boolean" || typeof duplicate.semantic_duplicate !== "boolean"
        || typeof duplicate.same_request !== "boolean") throw new AnalysisError(503, "duplicate_check_unavailable");
      signal.throwIfAborted();
      const summary = assessDonation(facts, duplicate);
      return json({ review_type: "donation_evidence", evidence_id: id, submitted_at: evidence.submitted_at, sha256: digest,
        analyzed_at: new Date().toISOString(), model: config.model ?? DEFAULT_MODEL,
        prompt_version: DONATION_PROMPT_VERSION, human_review_required: true, authenticity_verified: false,
        writing_permission_granted: false,
        notice: "문자도 기부 증빙으로 판단해요. 증빙 충족은 원본 진위·제출자 본인·학교 납입 확인의 보증이 아니며, 글 작성은 운영자 승인 후 가능해요.",
        assessment: facts.visual_review, summary });
    } catch (error) {
      if (signal.aborted) return json({ error: "analysis_timeout" }, 504);
      if (error instanceof AnalysisError) return json({ error: error.code }, error.status);
      return json({ error: "analysis_unavailable" }, 503);
    } finally {
      if (lockedId) active.delete(lockedId);
    }
  };
}

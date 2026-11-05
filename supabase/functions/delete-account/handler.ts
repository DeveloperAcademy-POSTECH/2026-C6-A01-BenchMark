type Config = { url: string; publicKey: string; serviceKey: string };
type ObjectEntry = { bucket: "oi-evidence" | "oi-story-media"; name: string };
const uuid = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const tokenPattern = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

class DeleteFailure extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) { super(code); this.status = status; this.code = code; }
}

function reply(body: object, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

async function readJSON(body: ReadableStream<Uint8Array> | null, max: number): Promise<unknown> {
  const reader = body?.getReader();
  if (!reader) throw new DeleteFailure(400, "invalid_request");
  const decoder = new TextDecoder();
  let result = "", bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) return JSON.parse(result + decoder.decode());
      bytes += value.byteLength;
      if (bytes > max) throw new DeleteFailure(413, "request_too_large");
      result += decoder.decode(value, { stream: true });
    }
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_object");
  return value as Record<string, unknown>;
}

export function createHandler(config: Config, fetcher: typeof fetch = fetch, clock = Date.now) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
    const authorization = request.headers.get("authorization");
    const primary = authorization?.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (primary.length > 16384 || !tokenPattern.test(primary)) return reply({ error: "authentication_required" }, 401);
    if (!config.url || !config.publicKey || !config.serviceKey) return reply({ error: "not_configured" }, 503);
    if (request.headers.get("content-type")?.split(";")[0] !== "application/json") return reply({ error: "json_required" }, 415);
    const signal = AbortSignal.timeout(42_000);
    const base = config.url.replace(/\/$/, "");
    const send = (path: string, init: RequestInit) => fetcher(base + path, { ...init, signal, redirect: "error" });
    const serviceHeaders = { apikey: config.serviceKey, Authorization: "Bearer " + config.serviceKey, "Content-Type": "application/json" };
    let input: Record<string, unknown>;
    try { input = record(await readJSON(request.body, 20000)); }
    catch (error) { return error instanceof DeleteFailure ? reply({ error: error.code }, error.status) : reply({ error: "invalid_request" }, 400); }
    if (typeof input.account_id !== "string" || !uuid.test(input.account_id) || input.consent !== true
      || typeof input.proof !== "string" || input.proof.length > 16384 || !tokenPattern.test(input.proof)
      || Object.keys(input).some(key => !["account_id", "consent", "proof"].includes(key))) {
      return reply({ error: "invalid_request" }, 400);
    }
    let prepared = false;
    try {
      const verify = async (token: string, recent: boolean) => {
        const response = await send("/auth/v1/user", { headers: { apikey: config.publicKey, Authorization: "Bearer " + token } });
        if (!response.ok) { await response.body?.cancel(); throw new DeleteFailure(response.status >= 500 ? 503 : 401, "authentication_failed"); }
        const user = record(await readJSON(response.body, 65536));
        const raw = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
        const claims = record(JSON.parse(atob(raw + "=".repeat((4 - raw.length % 4) % 4))));
        const now = clock() / 1000;
        if (typeof user.id !== "string" || !uuid.test(user.id) || claims.sub !== user.id || claims.iss !== base + "/auth/v1"
          || claims.role !== "authenticated" || typeof claims.exp !== "number" || claims.exp <= now
          || typeof claims.session_id !== "string" || !uuid.test(claims.session_id)) throw new DeleteFailure(401, "authentication_failed");
        if (recent && (!Array.isArray(claims.amr) || !claims.amr.some(entry => entry?.method === "oauth"
          && typeof entry.timestamp === "number" && entry.timestamp >= now - 600 && entry.timestamp <= now + 30))) {
          throw new DeleteFailure(401, "recent_login_required");
        }
        return { user: user.id, session: claims.session_id };
      };
      const current = await verify(primary, false);
      const proof = await verify(input.proof, true);
      const rpc = async (action: "prepare" | "finish") => {
        const response = await send("/rest/v1/rpc/oi_delete_account", { method: "POST", headers: serviceHeaders,
          body: JSON.stringify({ p_action: action, p_account: input.account_id, p_user: current.user, p_session: current.session,
            p_proof_user: proof.user, p_proof_session: proof.session }) });
        if (!response.ok) {
          await response.body?.cancel();
          throw new DeleteFailure(response.status === 403 ? 403 : 503, response.status === 403 ? "account_proof_mismatch" : "deletion_unavailable");
        }
        return record(await readJSON(response.body, 256 * 1024));
      };
      for (let batch = 0; batch < 20; batch++) {
        const result = await rpc("prepare");
        prepared = true;
        if (!Array.isArray(result.files) || result.files.length > 100) throw new Error("invalid_inventory");
        const files: ObjectEntry[] = result.files.map(value => {
          const item = record(value);
          if ((item.bucket !== "oi-evidence" && item.bucket !== "oi-story-media") || typeof item.name !== "string"
            || item.name.length > 1024 || !item.name.split("/").every(segment => segment && segment !== "." && segment !== "..")) {
            throw new Error("invalid_inventory");
          }
          return { bucket: item.bucket, name: item.name };
        });
        if (!files.length) {
          const result = await rpc("finish");
          if (result.deleted !== true || typeof result.apple_revocation_required !== "boolean"
            || !Array.isArray(result.deleted_member_ids) || !result.deleted_member_ids.length
            || !result.deleted_member_ids.every(id => typeof id === "string" && uuid.test(id))) throw new Error("invalid_receipt");
          return reply({ deleted: true, apple_revocation_required: result.apple_revocation_required, deleted_member_ids: result.deleted_member_ids });
        }
        for (const bucket of ["oi-evidence", "oi-story-media"] as const) {
          const prefixes = files.filter(item => item.bucket === bucket).map(item => item.name);
          if (!prefixes.length) continue;
          const response = await send("/storage/v1/object/" + bucket, { method: "DELETE", headers: serviceHeaders,
            body: JSON.stringify({ prefixes }) });
          await response.body?.cancel();
          if (!response.ok) throw new DeleteFailure(503, "deletion_incomplete");
        }
      }
      return reply({ error: "deletion_incomplete" }, 503);
    } catch (error) {
      if (prepared) return reply({ error: "deletion_incomplete" }, 503);
      return error instanceof DeleteFailure ? reply({ error: error.code }, error.status) : reply({ error: "deletion_unavailable" }, 503);
    }
  };
}

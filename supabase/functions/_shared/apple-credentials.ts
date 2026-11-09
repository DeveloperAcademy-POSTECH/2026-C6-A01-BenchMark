export type AppleConfiguration = {
  clientId: string;
  teamId: string;
  keyId: string;
  privateKey: string;
  encryptionKey: string;
};

const issuer = "https://appleid.apple.com";
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export const isAppleCode = (value: unknown): value is string =>
  typeof value === "string" && /^[\x21-\x7e]{1,2048}$/.test(value);

export function appleConfiguration(get: (key: string) => string | undefined): AppleConfiguration | undefined {
  const teamId = get("APPLE_SIGN_IN_TEAM_ID");
  const keyId = get("APPLE_SIGN_IN_KEY_ID");
  const privateKey = get("APPLE_SIGN_IN_PRIVATE_KEY");
  const encryptionKey = get("APPLE_TOKEN_ENCRYPTION_KEY");
  if (!teamId || !keyId || !privateKey || !encryptionKey) return;
  return { clientId: "com.Spero.OiDonation", teamId, keyId, privateKey, encryptionKey };
}

function decodeBase64(value: string) {
  return Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), character => character.charCodeAt(0));
}

function base64URL(value: Uint8Array): string {
  return btoa(String.fromCharCode(...value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function clientSecret(config: AppleConfiguration) {
  const key = await crypto.subtle.importKey("pkcs8", decodeBase64(config.privateKey
    .replace(/\\n/g, "\n").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "")),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: config.keyId };
  const claims = { iss: config.teamId, sub: config.clientId, aud: issuer, iat: now, exp: now + 600 };
  const message = [header, claims].map(value => base64URL(encoder.encode(JSON.stringify(value)))).join(".");
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(message));
  return `${message}.${base64URL(new Uint8Array(signature))}`;
}

async function appleRequest(config: AppleConfiguration, path: "token" | "revoke", fields: Record<string, string>,
  fetcher: typeof fetch, signal: AbortSignal) {
  return fetcher(`${issuer}/auth/${path}`, {
    method: "POST", redirect: "error", signal,
    body: new URLSearchParams({ client_id: config.clientId, client_secret: await clientSecret(config), ...fields }),
  });
}

export async function exchangeAppleCode(config: AppleConfiguration, code: string, fetcher: typeof fetch, signal: AbortSignal) {
  const response = await appleRequest(config, "token", { grant_type: "authorization_code", code }, fetcher, signal);
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error("apple_token_exchange_failed");
  }
  const result = await response.json();
  if (typeof result?.id_token !== "string" || typeof result.refresh_token !== "string" ||
    !/^[\x21-\x7e]{1,4096}$/.test(result.refresh_token)) throw new Error("invalid_apple_token_response");

  // The ID token is received directly from Apple's HTTPS token endpoint, never from the app.
  const [, payload] = result.id_token.split(".");
  const claims = JSON.parse(decoder.decode(decodeBase64(payload ?? "")));
  if (claims.iss !== issuer || claims.aud !== config.clientId || typeof claims.exp !== "number" ||
    claims.exp <= Date.now() / 1000 || typeof claims.sub !== "string" || !/^[\x21-\x7e]{1,255}$/.test(claims.sub)) {
    throw new Error("invalid_apple_identity");
  }
  return { subject: claims.sub as string, refreshToken: result.refresh_token as string };
}

async function encryptionKey(config: AppleConfiguration) {
  const bytes = decodeBase64(config.encryptionKey);
  if (bytes.length !== 32) throw new Error("invalid_apple_encryption_key");
  return crypto.subtle.importKey("raw", bytes, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

export async function encryptAppleToken(config: AppleConfiguration, subject: string, token: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: encoder.encode(subject) },
    await encryptionKey(config), encoder.encode(token));
  return `${base64URL(iv)}.${base64URL(new Uint8Array(ciphertext))}`;
}

export async function decryptAppleToken(config: AppleConfiguration, subject: string, token: string) {
  const [iv, ciphertext] = token.split(".");
  return decoder.decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv: decodeBase64(iv), additionalData: encoder.encode(subject) },
    await encryptionKey(config), decodeBase64(ciphertext)));
}

export async function revokeAppleToken(config: AppleConfiguration, token: string, fetcher: typeof fetch, signal: AbortSignal) {
  const response = await appleRequest(config, "revoke", { token, token_type_hint: "refresh_token" }, fetcher, signal);
  await response.body?.cancel();
  return response.ok;
}

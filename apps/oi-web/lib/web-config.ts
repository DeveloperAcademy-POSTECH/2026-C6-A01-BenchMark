export function authConfig() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key || key.startsWith("sb_secret_")) return null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" || parsed.username || parsed.password) return null;
    return { url: parsed.origin, key };
  } catch { return null; }
}

export function officialDonationUrl(value = process.env.POSTECH_DONATION_URL) {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password ||
        !(url.hostname === "postech.ac.kr" || url.hostname.endsWith(".postech.ac.kr"))) return null;
    return url.href;
  } catch { return null; }
}

export function loginDestination(value: unknown) {
  return value === "/donate" ? "/donate" : "/";
}

export function appOrigin(value = process.env.APP_ORIGIN) {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.origin !== value || url.username || url.password) return null;
    if (url.protocol !== "https:" && !(url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname))) return null;
    return url.origin;
  } catch { return null; }
}

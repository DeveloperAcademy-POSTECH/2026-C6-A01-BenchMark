import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { authConfig } from "@/lib/web-config";

export async function authClient() {
  const config = authConfig();
  if (!config) return null;
  const jar = await cookies();
  return createServerClient(config.url, config.key, {
    global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) }) },
    cookieOptions: { httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax", path: "/" },
    cookies: {
      getAll: () => jar.getAll(),
      setAll: (values) => {
        try { values.forEach(({ name, value, options }) => jar.set(name, value, options)); }
        catch { /* Server Components cannot write cookies; proxy owns refresh. */ }
      },
    },
  });
}

export async function currentAccount() {
  const client = await authClient();
  if (!client) return { user: null, unavailable: true };
  try {
    const { data, error } = await client.auth.getUser();
    return { user: data.user, unavailable: !!error && error.name !== "AuthSessionMissingError" };
  } catch { return { user: null, unavailable: true }; }
}

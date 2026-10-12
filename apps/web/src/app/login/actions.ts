"use server";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { authClient } from "@/lib/auth/server";
import { appOrigin, loginDestination } from "@/lib/web-config";

export async function login(form: FormData) {
  const client = await authClient();
  if (!client) redirect("/login?error=config");
  const origin = appOrigin();
  if (!origin || (await headers()).get("origin") !== origin)
    redirect("/login?error=config");
  const next = loginDestination(form.get("next"));
  const callback = new URL("/auth/callback", origin);
  callback.searchParams.set("next", next);
  let target: string | undefined;
  try {
    const { data, error } = await client.auth.signInWithOAuth({
      provider: "google", options: { redirectTo: callback.href, skipBrowserRedirect: true },
    });
    if (!error) target = data.url;
  } catch { /* Provider failures return to a retryable login screen. */ }
  if (!target) redirect(`/login?error=provider&next=${encodeURIComponent(next)}`);
  redirect(target);
}

export async function logout() {
  const client = await authClient();
  if (!client) redirect("/login?error=config");
  let failed = false;
  try { const { error } = await client.auth.signOut({ scope: "local" }); failed = !!error; }
  catch { failed = true; }
  if (failed) redirect("/login?error=logout");
  redirect("/");
}

import { test, expect } from "@playwright/test";
test("configured Google login writes PKCE cookie and returns only to donation page", async ({ page, context }) => {
  test.skip(process.env.TEST_AUTH_CONFIGURED !== "true", "Requires a server configured with the Android Supabase project.");
  let target: URL | undefined;
  await page.route("https://*.supabase.co/auth/v1/authorize?**", async route => {
    target = new URL(route.request().url());
    await route.fulfill({ status: 200, contentType: "text/html", body: "<p>OAuth navigation verified; no account login performed.</p>" });
  });
  await page.goto("/login?next=%2Fdonate");
  await page.getByRole("button", { name: "Google 계정으로 계속하기" }).click();
  await expect(page.getByText("OAuth navigation verified")).toBeVisible();
  expect(target?.searchParams.get("provider")).toBe("google");
  expect(target?.searchParams.get("code_challenge_method")).toBe("s256");
  expect(target?.searchParams.get("code_challenge")).toMatch(/^[A-Za-z0-9_-]{43}$/);
  const callback = new URL(target!.searchParams.get("redirect_to")!);
  expect(callback.origin).toBe(process.env.TEST_BASE_URL || "http://127.0.0.1:4314");
  expect(callback.pathname).toBe("/auth/callback");
  expect(callback.searchParams.get("next")).toBe("/donate");
  const verifier = (await context.cookies()).find(cookie => cookie.name.includes("code-verifier"));
  expect(verifier?.httpOnly).toBe(true);
  expect(verifier?.sameSite).toBe("Lax");
  expect(verifier?.secure).toBe(true);
});

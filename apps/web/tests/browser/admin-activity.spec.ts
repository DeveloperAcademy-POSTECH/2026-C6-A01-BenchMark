import { test, expect } from "@playwright/test";

test("admin history survives logout and browser-state restoration while a fresh browser is tracked", async ({ page, context, browser, baseURL }) => {
  const origin = baseURL!;
  await page.goto("/admin");
  const login = await page.request.post("/api/admin/session", {
    headers: { origin }, data: { password: process.env.ADMIN_PASSWORD },
  });
  expect(login.status()).toBe(200);
  const marker = (await context.cookies()).find(cookie => cookie.name === "mat_activity_excluded")!;
  expect(marker.httpOnly).toBe(true);
  expect(marker.secure).toBe(true);
  expect(marker.expires).toBeGreaterThan(Date.now() / 1000 + 399 * 86400);
  const logout = await page.request.delete("/api/admin/session", { headers: { origin } });
  expect(logout.status()).toBe(200);
  expect((await context.cookies()).some(cookie => cookie.name === "mat_admin")).toBe(false);
  const restored = await browser.newContext({ storageState: await context.storageState() });
  const fresh = await browser.newContext();
  try {
    const restoredPage = await restored.newPage();
    const response = restoredPage.waitForResponse(r => r.url().endsWith("/api/activity") && r.request().method() === "POST");
    await restoredPage.goto(`${origin}/stories`);
    expect((await response).status()).toBe(200);
    expect((await response).headers()["cache-control"]).toBe("private, no-store");
    expect((await restored.request.get(`${origin}/api/admin/activity`)).status()).toBe(401);
    const freshPage = await fresh.newPage();
    const freshResponse = freshPage.waitForResponse(r => r.url().endsWith("/api/activity") && r.request().method() === "POST");
    await freshPage.goto(`${origin}/stories`);
    expect((await freshResponse).status()).toBe(200);
    expect((await freshResponse).headers()["cache-control"]).toBe("no-store");
  } finally {
    await restored.close();
    await fresh.close();
  }
});

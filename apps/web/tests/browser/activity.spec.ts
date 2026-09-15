import { test, expect } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { mkdir } from "node:fs/promises";
import { Pool } from "pg";
import sharp from "sharp";

test("activity survives transport failure, respects visibility, distinguishes navigation and exports from admin", async ({ page }) => {
  test.setTimeout(120000);
  if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const storyId = randomUUID();
  const photo = await sharp({ create: { width: 400, height: 400, channels: 3, background: "#e7dfbb" } }).jpeg().toBuffer();
  const payloads: { events: { id: string; visitId: string; sessionId: string; name: string; path: string; properties: Record<string, unknown> }[] }[] = [];
  const errors: string[] = []; page.on("pageerror", e => errors.push(e.message));
  let attempts = 0;
  try {
    await pool.query("INSERT INTO mat_stories(id,mat_number,mat_size,display_name,title,story,photo,payment_verified,published) VALUES($1,9911,'small','활동 검증','활동 검증 이야기','개인 내용 검증',$2,true,true)", [storyId, photo]);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.route("**/api/activity", async route => {
      payloads.push(route.request().postDataJSON());
      attempts++;
      if (attempts === 1) { await route.fetch(); await route.abort("connectionclosed"); }
      else await route.continue();
    });
    await page.goto(`/stories/${storyId}?phone=private-query`);
    await expect(page.getByRole("button", { name: /공감해요/ })).toBeEnabled();
    await page.getByRole("button", { name: /공감해요/ }).click();
    await expect(page.getByRole("button", { name: /공감해요/ })).toBeDisabled();
    await page.evaluate(() => scrollTo(0, document.documentElement.scrollHeight));
    await expect.poll(() => attempts, { timeout: 20000 }).toBeGreaterThanOrEqual(2);
    const view = payloads.flatMap(p => p.events).find(e => e.name === "page_view")!;
    expect(view).toBeTruthy();
    expect(payloads[1].events.some(e => e.id === view.id)).toBe(true);
    const rows = () => pool.query("SELECT * FROM mat_activity_events WHERE story_id=$1 ORDER BY occurred_at", [storyId]).then(r => r.rows);
    await expect.poll(async () => (await rows()).filter(r => r.name === "reaction_success").length).toBe(1);
    expect((await rows()).filter(r => r.name === "page_view")).toHaveLength(1);
    // Repeated scrolling and local state updates must not create a second view or duplicate bucket.
    await page.evaluate(() => { scrollTo(0, 0); scrollTo(0, document.documentElement.scrollHeight); });
    await expect.poll(async () => (await rows()).some(r => r.name === "scroll_depth" && r.properties.percent === 100), { timeout: 10000 }).toBe(true);
    await page.evaluate(() => {
      Object.defineProperty(document, "visibilityState", { configurable: true, value: "hidden" });
      document.dispatchEvent(new Event("visibilitychange"));
    });
    await page.waitForTimeout(1000);
    const before = (await rows()).filter(r => r.name === "active_time").reduce((n, r) => n + r.properties.milliseconds, 0);
    await page.waitForTimeout(16000);
    const hidden = (await rows()).filter(r => r.name === "active_time").reduce((n, r) => n + r.properties.milliseconds, 0);
    expect(hidden).toBe(before);
    await page.evaluate(() => {
      delete (document as unknown as { visibilityState?: string }).visibilityState;
      document.dispatchEvent(new Event("visibilitychange"));
    });
    await page.reload();
    await expect.poll(async () => (await rows()).filter(r => r.name === "page_view").length, { timeout: 10000 }).toBe(2);
    const views = (await rows()).filter(r => r.name === "page_view");
    expect(views[0].session_id).toBe(views[1].session_id);
    expect(views[0].visit_id).not.toBe(views[1].visit_id);
    await page.getByRole("link", { name: /다른 자리의 이야기도/ }).click();
    await expect(page).toHaveURL(/\/stories$/);
    await page.goBack();
    await expect.poll(async () => (await rows()).filter(r => r.name === "page_view").length, { timeout: 10000 }).toBe(3);
    await page.evaluate(() => {
      const saved = JSON.parse(sessionStorage.getItem("mat-activity-session")!);
      saved.last = Date.now() - 31 * 60 * 1000;
      sessionStorage.setItem("mat-activity-session", JSON.stringify(saved));
    });
    await page.reload();
    await expect.poll(async () => (await rows()).filter(r => r.name === "page_view").length, { timeout: 10000 }).toBe(4);
    const expiredViews = (await rows()).filter(r => r.name === "page_view");
    expect(expiredViews[3].session_id).not.toBe(expiredViews[0].session_id);
    expect(JSON.stringify(payloads)).not.toContain("private-query");
    expect(JSON.stringify(payloads)).not.toContain("개인 내용 검증");
    const all = await rows();
    const scrolls = all.filter(r => r.name === "scroll_depth");
    expect(new Set(scrolls.map(r => `${r.visit_id}:${r.properties.percent}`)).size).toBe(scrolls.length);
    await page.goto("/admin");
    await page.getByLabel("비밀번호", { exact: true }).fill(process.env.ADMIN_PASSWORD!);
    await page.getByRole("button", { name: "관리자 페이지로 이동" }).click();
    await expect(page.getByRole("heading", { name: "페이지 활동 로그" })).toBeVisible();
    await page.getByLabel("스토리 ID", { exact: true }).fill(storyId);
    await page.getByRole("button", { name: "로그 조회", exact: true }).click();
    await expect(page.getByRole("region", { name: "활동 로그 표" })).toBeVisible();
    await mkdir("../../docs/screenshots", { recursive: true });
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      await page.locator(".activity-panel").screenshot({ path: `../../docs/screenshots/activity-admin-${width}.png` });
    }
    const downloadPromise = page.waitForEvent("download");
    await page.getByRole("button", { name: "현재 조건으로 CSV 저장" }).click();
    const download = await downloadPromise; expect(download.suggestedFilename()).toBe("page-activity.csv");
    const stream = await download.createReadStream(); const chunks: Buffer[] = [];
    for await (const chunk of stream!) chunks.push(Buffer.from(chunk));
    expect(Buffer.concat(chunks).toString()).toContain(storyId);
    expect(errors).toEqual([]);
  } finally {
    await page.goto("about:blank");
    await pool.query("DELETE FROM mat_activity_events WHERE story_id=$1 OR session_id=$2", [storyId, payloads[0]?.events[0]?.sessionId ?? randomUUID()]);
    await pool.query("DELETE FROM mat_stories WHERE id=$1", [storyId]);
    await pool.end();
  }
});


test("transport retries are capped and unavailable analytics does not block navigation", async ({ page }) => {
  const counts = new Map<string, number>();
  let viewId = "";
  await page.route("**/api/activity", async route => {
    const { events } = route.request().postDataJSON();
    for (const event of events) {
      counts.set(event.id, (counts.get(event.id) || 0) + 1);
      if (event.name === "page_view") viewId ||= event.id;
    }
    await route.fulfill({ status: 503, contentType: "application/json", body: '{"error":"Test outage"}' });
  });
  await page.goto("/stories");
  await expect.poll(() => counts.get(viewId), { timeout: 20000 }).toBe(3);
  await page.waitForTimeout(6000);
  expect(counts.get(viewId)).toBe(3);
  await page.getByRole("link", { name: /나도 이야기 남기기/ }).click();
  await expect(page.getByRole("heading", { name: "기부 예약", exact: true })).toBeVisible();
});

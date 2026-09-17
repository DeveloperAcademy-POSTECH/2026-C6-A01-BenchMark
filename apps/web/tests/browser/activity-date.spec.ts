import { test, expect } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { activityKoreaTime } from "../../src/lib/activity";

test.use({ timezoneId: "America/Los_Angeles" });
test("date filter and CSV stay on Korean time outside Korea", async ({ page, context, baseURL }) => {
  if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const session = randomUUID();
  const path = `/stories/${randomUUID()}`;
  const day = activityKoreaTime(new Date(Date.now() - 3 * 86400000).toISOString()).slice(0, 10);
  const start = Date.parse(`${day}T00:00:00+09:00`);
  try {
    for (const offset of [-1, 0, 86399999, 86400000]) {
      await pool.query("INSERT INTO mat_activity_events(id,visit_id,session_id,name,occurred_at,path,properties) VALUES($1,$2,$3,'page_view',$4,$5,'{}')", [randomUUID(), randomUUID(), session, new Date(start + offset), path]);
    }
    const login = await context.request.post(`${baseURL}/api/admin/session`, {
      headers: { origin: baseURL!, "x-forwarded-for": "192.0.2.34" },
      data: { password: process.env.ADMIN_PASSWORD },
    });
    expect(login.status()).toBe(200);
    await page.goto("/admin");
    await page.getByLabel("페이지 경로", { exact: true }).fill(path);
    await page.getByRole("button", { name: "일자별", exact: true }).click();
    await page.getByLabel("조회 일자 (한국 시간)").fill(day);
    await expect(page.getByLabel("시작 시각", { exact: true })).toBeDisabled();
    await page.getByRole("button", { name: "로그 조회", exact: true }).click();
    await expect(page.getByRole("status")).toHaveText("2건 표시");
    await expect(page.getByRole("cell", { name: `${day} 00:00:00`, exact: true })).toBeVisible();
    await expect(page.getByRole("cell", { name: `${day} 23:59:59`, exact: true })).toBeVisible();
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      await page.locator(".activity-panel").screenshot({ path: `../../docs/screenshots/activity-date-${width}.png` });
    }
    const pending = page.waitForEvent("download");
    await page.getByRole("button", { name: "현재 조건으로 CSV 저장" }).click();
    const download = await pending;
    expect(download.suggestedFilename()).toBe(`page-activity-${day}.csv`);
    const chunks: Buffer[] = [];
    for await (const chunk of (await download.createReadStream())!) chunks.push(Buffer.from(chunk));
    const csv = Buffer.concat(chunks).toString();
    expect(csv.trim().split("\r\n")).toHaveLength(3);
    expect(csv).toContain(`${day}T00:00:00.000+09:00`);
    await page.getByRole("button", { name: "기간·시간", exact: true }).click();
    await expect(page.getByRole("region", { name: "활동 로그 표" })).toHaveCount(0);
    await expect(page.getByLabel("시작 시각", { exact: true })).toBeEnabled();
    await page.getByLabel("시작 시각", { exact: true }).fill(`${day}T00:00`);
    await page.getByLabel("종료 시각 (미포함)").fill(`${day}T00:01`);
    await page.getByRole("button", { name: "로그 조회", exact: true }).click();
    await expect(page.getByRole("status")).toHaveText("1건 표시");
    await page.locator("select[name=name]").selectOption("scroll_depth");
    await page.getByRole("button", { name: "로그 조회", exact: true }).click();
    await expect(page.getByRole("status")).toHaveText("해당 조건의 활동 로그가 없습니다.");
    await page.getByLabel("종료 시각 (미포함)").fill(`${day}T00:00`);
    await page.getByRole("button", { name: "로그 조회", exact: true }).click();
    await expect(page.locator(".activity-panel").getByRole("alert")).toHaveText("종료 시각은 시작 시각보다 늦게 선택해주세요.");
    await page.getByRole("button", { name: "오늘", exact: true }).click();
    await expect(page.getByLabel("조회 일자 (한국 시간)")).toHaveValue(activityKoreaTime(new Date().toISOString()).slice(0, 10));
    await expect(page.getByRole("button", { name: "일자별", exact: true })).toHaveAttribute("aria-pressed", "true");
    await page.getByRole("button", { name: "어제", exact: true }).click();
    await expect(page.getByLabel("조회 일자 (한국 시간)")).toHaveValue(activityKoreaTime(new Date(Date.now() - 86400000).toISOString()).slice(0, 10));
    await page.getByRole("button", { name: "기간·시간", exact: true }).click();
    await expect(page.getByLabel("시작 시각", { exact: true })).toHaveValue(`${day}T00:00`);
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 1000 });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      await page.locator(".activity-panel").screenshot({ path: `../../docs/screenshots/activity-range-${width}.png` });
    }
  } finally {
    await pool.query("DELETE FROM mat_activity_events WHERE session_id=$1", [session]);
    await pool.end();
  }
});

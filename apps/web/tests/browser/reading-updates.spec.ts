import { test, expect } from "@playwright/test";
import { Pool } from "pg";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

test("anonymous copy, section order and cancellable reactions survive failures and reload", async ({ page }) => {
  if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const id = randomUUID();
  const photo = await sharp({ create: { width: 400, height: 300, channels: 3, background: "#e4dec4" } }).jpeg().toBuffer();
  try {
    await pool.query("INSERT INTO mat_stories(id,mat_number,mat_size,display_name,title,story,photo,payment_verified,published) VALUES($1,9919,'small','익명','검증용 이야기','검증용 익명 이야기입니다.',$2,true,true)", [id, photo]);
    for (const path of ["/", `/stories/${id}`]) {
      await page.goto(path);
      await expect(page.locator(".donor-intro .eyebrow")).toContainText("익명의 선물");
      await expect(page.locator(".story-letter span")).toHaveCount(0);
      expect(await page.locator(".story-detail").evaluate(node => Array.from(node.children).filter(child => child.matches(".donation,.usage-guide")).map(child => child.classList.contains("donation") ? "donation" : "guide"))).toEqual(["donation", "guide"]);
      for (const width of [320,390,1440]) {
        await page.setViewportSize({ width, height: 900 });
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
        await expect(page.locator(".donation")).toBeVisible();
        await expect(page.locator(".usage-guide")).toBeVisible();
        const donationBox = await page.locator(".donation").boundingBox();
        const guideBox = await page.locator(".usage-guide").boundingBox();
        expect(guideBox!.y - donationBox!.y - donationBox!.height).toBeGreaterThanOrEqual(34);
      }
    }
    const labels = ["좋아요", "공감해요", "슬퍼요", "응원해요"];
    for (const label of labels) {
      const button = page.getByRole("button", { name: new RegExp(label) });
      await expect(button).toBeEnabled(); await button.click();
      await expect(button).toHaveAttribute("aria-pressed", "true");
      await expect(button).toBeEnabled(); await button.click();
      await expect(button).toHaveAttribute("aria-pressed", "false");
      await expect(button).toHaveAccessibleName(`${label} 0개`);
    }
    await page.reload();
    await expect(page.getByRole("button", { name: "좋아요 0개" })).toBeEnabled();
    const like = page.getByRole("button", { name: /좋아요/ });
    await like.click(); await expect(like).toHaveAttribute("aria-pressed", "true");
    await page.route("**/reaction", async route => {
      if (route.request().postDataJSON().action === "remove") {
        await route.fetch();
        await route.abort("failed");
      } else await route.continue();
    });
    await like.click();
    await expect(like).toHaveAttribute("aria-pressed", "false");
    await expect(like).toBeEnabled();
    await expect(like).toHaveAccessibleName("좋아요 0개");
    await page.unroute("**/reaction");
    await like.click(); await expect(like).toHaveAttribute("aria-pressed", "true");
    await page.route("**/reaction", route => route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ error: "검증용 장애" }) }));
    await like.click();
    await expect(like).toBeDisabled();
    await expect(page.locator(".reaction-wrap [role=alert]")).toContainText("새로고침");
    await page.unroute("**/reaction");
    await page.reload(); await expect(like).toHaveAttribute("aria-pressed", "true");
    await page.setViewportSize({ width: 390, height: 844 });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: fileURLToPath(new URL("../../../../docs/screenshots/reading-updates-mobile.png", import.meta.url)), fullPage: true });
    await pool.query("UPDATE mat_stories SET display_name='검증용 운영팀' WHERE id=$1", [id]);
    await page.reload();
    await expect(page.locator(".donor-intro .eyebrow")).toContainText("검증용 운영팀님의 선물");
    await expect(page.locator(".story-letter span")).toHaveText("이 자리를 선물한 검증용 운영팀 드림");
    await pool.query("UPDATE mat_stories SET published=false WHERE id=$1", [id]);
    await page.goto("/");
    await expect(page).toHaveURL("/stories");
    await expect(page.locator(".empty-state")).toBeVisible();
  } finally {
    await pool.query("DELETE FROM mat_stories WHERE id=$1", [id]);
    await pool.end();
  }
});

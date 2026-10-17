import { test, expect } from "@playwright/test";

const variants = ["editorial", "immersive", "tomorrow"] as const;
for (const width of [320, 390, 1440]) {
  for (const variant of variants) {
    test(`${variant}: ${width}px layout, navigation and images`, async ({ page }) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.setViewportSize({ width, height: 950 });
      const response = await page.goto(`/concepts/${variant}`);
      expect(response?.status()).toBe(200);
      await expect(page.locator("h1")).toHaveCount(1);
      await expect(page.locator("main")).toHaveCount(1);
      await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
      expect(await page.locator(".site-header").count()).toBe(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      await page.keyboard.press("Tab");
      await expect(page.getByRole("link", { name: "본문으로 바로가기" })).toBeFocused();
      await page.keyboard.press("Enter");
      await expect(page).toHaveURL(/#content$/);
      for (const photo of await page.locator("img").all()) {
        await photo.scrollIntoViewIfNeeded();
        await expect.poll(() => photo.evaluate((image: HTMLImageElement) => image.complete && image.naturalWidth > 0)).toBe(true);
      }
      for (const anchor of await page.locator('a[href^="#"]').all()) {
        const href = await anchor.getAttribute("href");
        expect(await page.locator(href!).count()).toBe(1);
      }
      const pilotLinks = page.locator('a[href="https://mat-web-production.up.railway.app"]');
      expect(await pilotLinks.count()).toBeGreaterThan(0);
      expect(errors).toEqual([]);
    });
  }
}

test("all three concepts remain reachable through the preview switcher", async ({ page }) => {
  await page.goto("/concepts/editorial");
  for (const [label, route] of [["02 Make room", "immersive"], ["03 Dear tomorrow", "tomorrow"], ["01 Editorial", "editorial"]]) {
    await page.getByRole("navigation", { name: "디자인 초안 선택" }).last().getByRole("link", { name: label }).click();
    await expect(page).toHaveURL(new RegExp(`/concepts/${route}$`));
    await expect(page.locator("h1")).toBeVisible();
    await expect(page.locator(".site-header")).toHaveCount(0);
  }
});

test("tomorrow questions can be expanded using the keyboard", async ({ page }) => {
  await page.goto("/concepts/tomorrow");
  const question = page.locator("summary").nth(1);
  await question.focus();
  await page.keyboard.press("Enter");
  await expect(page.locator("details").nth(1)).toHaveAttribute("open", "");
  await page.keyboard.press("Enter");
  await expect(page.locator("details").nth(1)).not.toHaveAttribute("open", "");
});

test("pilot shell remains available outside the concept routes", async ({ page }) => {
  await page.goto("/camera");
  await expect(page.locator(".site-header")).toBeVisible();
  await expect(page.locator("main#main")).toHaveCount(1);
  await expect(page.getByRole("link", { name: "쉼, 펴 홈" })).toBeVisible();
});

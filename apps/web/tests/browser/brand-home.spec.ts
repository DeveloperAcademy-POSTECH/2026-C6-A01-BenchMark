import { test, expect } from "@playwright/test";

for (const width of [320, 390, 768, 1100, 1440, 1784, 1920]) {
  test(`confirmed design: ${width}px assets, fonts and navigation`, async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.setViewportSize({ width, height: 1000 });
    expect((await page.goto("/benchmark"))?.status()).toBe(200);
    await page.evaluate(() => document.fonts.ready);
    await expect(page.locator("h1")).toHaveText("BenchMark");
    await expect(page.locator("main")).toHaveCount(1);
    await expect(page.locator(".site-header")).toHaveCount(0);
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    for (const font of ["Griun OMIRI", "Hedvig Letters Serif", "Brand Pretendard"]) {
      expect(await page.evaluate(family => document.fonts.check(`20px "${family}"`), font)).toBe(true);
    }
    for (const image of await page.locator("img").all()) {
      await image.scrollIntoViewIfNeeded();
      await expect.poll(() => image.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth > 0)).toBe(true);
      const box = await image.boundingBox();
      expect(box!.width).toBeGreaterThan(100);
    }
    for (const anchor of await page.locator('a[href^="#"]').all()) {
      expect(await page.locator((await anchor.getAttribute("href"))!).count()).toBe(1);
    }
    await expect(page.locator('a[href="https://mat-web-production.up.railway.app"]')).toHaveCount(2);
    expect(errors).toEqual([]);
  });
}

test("confirmed design keyboard navigation and FAQ", async ({ page }) => {
  await page.goto("/benchmark");
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "본문으로 바로가기" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#content$/);
  await page.getByRole("link", { name: "벤치마크 알아보기" }).click();
  await expect(page).toHaveURL(/#belief$/);
  const question = page.locator("summary").nth(1);
  await question.focus();
  await page.keyboard.press("Enter");
  await expect(page.locator("details").nth(1)).not.toHaveAttribute("open", "");
  await page.keyboard.press("Enter");
  await expect(page.locator("details").nth(1)).toHaveAttribute("open", "");
});

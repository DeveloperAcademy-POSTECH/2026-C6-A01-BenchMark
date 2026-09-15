import { test, expect } from "@playwright/test";

test("mat amount presets show selection, update input, and preserve custom amounts", async ({ page }) => {
  await page.route("**/api/activity", route => route.fulfill({ status: 204 }));
  await page.goto("/reserve");
  const amount = page.getByRole("spinbutton", { name: "기부금액", exact: true });
  const small = page.getByRole("button", { name: /2~3인용/ });
  const large = page.getByRole("button", { name: /4~5인용/ });
  await expect(amount).toHaveValue("");
  await small.click();
  await expect(amount).toHaveValue("10000");
  await expect(small).toHaveAttribute("aria-pressed", "true");
  await expect(small).toContainText("선택됨");
  await large.focus();
  await large.press("Space");
  await expect(amount).toHaveValue("20000");
  await expect(large).toHaveAttribute("aria-pressed", "true");
  await expect(small).toHaveAttribute("aria-pressed", "false");
  expect(await large.evaluate(el => getComputedStyle(el).backgroundColor)).not.toBe(await small.evaluate(el => getComputedStyle(el).backgroundColor));
  await amount.fill("25000");
  await expect(amount).toHaveValue("25000");
  await expect(large).toHaveAttribute("aria-pressed", "false");
  await small.click();
  await expect(amount).toHaveValue("10000");
  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(small).toBeVisible();
    await expect(large).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.locator(".base-amounts").scrollIntoViewIfNeeded();
  await page.screenshot({ path: test.info().outputPath("amount-selection-mobile.png") });
});

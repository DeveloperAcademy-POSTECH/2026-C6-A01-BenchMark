import { test, expect } from "@playwright/test";
import { mkdir } from "node:fs/promises";
test("Oi home, donation and login remain usable at mobile and desktop widths", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toContainText("당신의 이야기");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.getByRole("link", { name: "기부 시작하기" }).click();
    await expect(page).toHaveURL(/\/donate$/);
    await expect(page.getByRole("status")).toContainText("공식 기부 연결 준비 중");
    await expect(page.getByText("학교에서 확인하기 전까지 기부 완료로 처리하지 않습니다.")).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.getByRole("link", { name: "로그인하고 돌아오기" }).click();
    await expect(page.getByRole("heading", { level: 1 })).toContainText("반가워요");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  }
  await page.goto("/auth/callback?error=access_denied&next=https://evil.test");
  await expect(page).toHaveURL(/\/login\?error=callback&next=%2F$/);
  await expect(page.locator(".error-message[role=alert]")).toContainText("취소되었거나");
  await mkdir("../../docs/web-oi", { recursive: true });
  for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    for (const path of ["/", "/donate", "/login"]) {
      await page.goto(path);
      await page.screenshot({ path: `../../docs/web-oi/${path.slice(1) || "home"}-${width}.png`, fullPage: true });
    }
  }
  expect(errors).toEqual([]);
});

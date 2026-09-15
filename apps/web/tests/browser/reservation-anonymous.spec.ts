import { test, expect } from "@playwright/test";
import { Pool } from "pg";
import sharp from "sharp";
import { fileURLToPath } from "node:url";

test("anonymous selection preserves drafts and saves an anonymous reservation", async ({ page }) => {
  if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  let reservationId = "";
  try {
    await page.goto("/reserve");
    await expect(page.locator(".story-guidance li")).toHaveCount(3);
    await expect(page.locator(".reservation-question legend").first()).toContainText("돗자리에 남길 이야기를 들려주세요");
    await expect(page.getByRole("textbox", { name: "스토리", exact: true })).toHaveAttribute("aria-describedby", "story-guidance reservation-bytes");
    const email = page.getByRole("textbox", { name: "이메일", exact: true });
    await expect(email).toHaveAttribute("type", "email");
    await expect(email).toHaveAttribute("required");
    const name = page.getByRole("textbox", { name: "성함", exact: true });
    const anonymous = page.getByRole("checkbox", { name: "익명", exact: true });
    await expect(anonymous).not.toBeChecked();
    await expect(name).toHaveAttribute("required");
    await name.fill("검증용 신청자");
    await anonymous.focus();
    await anonymous.press("Space");
    await expect(name).toBeDisabled();
    await expect(name).toHaveValue("익명");
    await expect(name).not.toHaveAttribute("required");
    await anonymous.press("Space");
    await expect(name).toBeEnabled();
    await expect(name).toHaveValue("검증용 신청자");
    await name.fill("");
    await anonymous.check();
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await expect(anonymous).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
    await page.setViewportSize({ width: 390, height: 844 });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: fileURLToPath(new URL("../../../../docs/screenshots/reservation-anonymous-mobile.png", import.meta.url)), fullPage: true });
    await expect(page.locator('input[name="phone"]')).toHaveCount(0);
    await email.fill("anonymous@example.test");
    await page.getByRole("textbox", { name: "마음을 담은 한 줄", exact: true }).fill("익명 신청 검증");
    await page.getByRole("textbox", { name: "스토리", exact: true }).fill("검증용 이야기입니다.");
    const photo = await sharp({ create: { width: 20, height: 20, channels: 3, background: "#eee5cb" } }).jpeg().toBuffer();
    await page.getByLabel("사진 추가", { exact: true }).setInputFiles({ name: "test.jpg", mimeType: "image/jpeg", buffer: photo });
    await page.getByRole("radio", { name: "기타", exact: true }).check();
    await page.getByRole("spinbutton", { name: "기부금액", exact: true }).fill("12500");
    await page.getByRole("button", { name: "기부 예약 접수하기" }).click();
    await page.getByLabel("기부자 스토리를 보고 흥미가 생겨서").check();
    await page.route("**/api/reservations", route => {
      const body = route.request().postData() || "";
      expect(body).toContain('name="isAnonymous"');
      expect(body).not.toContain('name="displayName"');
      expect(body).not.toContain('name="phone"');
      return route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ error: "검증용 접수 오류" }) });
    });
    await page.getByRole("button", { name: "예약 접수 완료하기" }).click();
    await expect(page.locator("dialog").getByRole("alert")).toHaveText("검증용 접수 오류");
    await expect(anonymous).toBeChecked();
    await expect(name).toBeDisabled();
    await page.unroute("**/api/reservations");
    const responsePromise = page.waitForResponse(response => response.url().endsWith("/api/reservations") && response.request().method() === "POST");
    await page.getByRole("button", { name: "예약 접수 완료하기" }).click();
    const response = await responsePromise;
    expect(response.status()).toBe(201);
    reservationId = (await response.json()).id;
    await expect(page.getByRole("heading", { name: "기부 예약이 접수됐어요." })).toBeVisible();
    const saved = (await pool.query("SELECT display_name,phone,email,payment_method FROM mat_reservations WHERE id=$1", [reservationId])).rows[0];
    expect(saved).toEqual({ display_name: "익명", phone: null, email: "anonymous@example.test", payment_method: "other" });
    await page.goto("/admin");
    await page.getByLabel("비밀번호", { exact: true }).fill(process.env.ADMIN_PASSWORD!);
    await page.getByRole("button", { name: "관리자 페이지로 이동" }).click();
    await page.getByText("익명 · 12,500원 예약", { exact: true }).click();
    await expect(page.locator('a[href^="tel:"]')).toHaveCount(0);
    await expect(page.getByRole("link", { name: "anonymous@example.test" })).toHaveAttribute("href", "mailto:anonymous@example.test");
    await page.getByRole("button", { name: "이 예약으로 이야기 등록" }).click();
    await expect(page.getByLabel("공개 이름")).toHaveValue("익명");
  } finally {
    if (reservationId) await pool.query("DELETE FROM mat_reservations WHERE id=$1", [reservationId]);
    await pool.end();
  }
});

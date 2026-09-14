import { test, expect } from "@playwright/test";
import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import { Pool } from "pg";

test("admin registration, publication, mobile reading and one-device reaction", async ({ page, browser }) => {
  if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const photo = await sharp({ create: { width: 1000, height: 750, channels: 3, background: "#e4dec4" } }).composite([{ input: Buffer.from('<svg width="1000" height="750"><text x="500" y="390" text-anchor="middle" font-family="sans-serif" font-size="42" fill="#536342">TEST PHOTO</text></svg>') }]).jpeg().toBuffer();
  const errors: string[] = []; page.on("pageerror", (error) => errors.push(error.message));
  let storyId = "";
  try {
    await page.goto("/admin");
    await page.getByLabel("비밀번호", { exact: true }).fill(process.env.ADMIN_PASSWORD!);
    await page.getByRole("button", { name: "관리자 페이지로 이동" }).click();
    await expect(page.getByRole("heading", { name: "이야기 관리" })).toBeVisible();
    await page.getByRole("button", { name: "+ 새 이야기 등록" }).click();
    await page.getByLabel("돗자리 번호", { exact: true }).fill("9902");
    await page.getByLabel("공개 이름").fill("검증용 운영팀");
    await page.getByLabel("사진 한 장").setInputFiles({ name: "test.jpg", mimeType: "image/jpeg", buffer: photo });
    await page.getByRole("textbox", { name: /^이야기/ }).fill("이 화면은 검증용 데이터입니다. 함께 쉬어 가는 자리에 작은 마음을 남깁니다.");
    await expect(page.getByLabel("내용 검토 완료 · 웹에 공개")).toBeDisabled();
    await page.getByLabel("입금 확인 완료").check();
    await page.getByLabel("내용 검토 완료 · 웹에 공개").check();
    await page.getByRole("button", { name: "저장하고 공개" }).click();
    await expect(page.getByRole("heading", { name: "#9902 · 검증용 운영팀" })).toBeVisible();
    storyId = (await pool.query("SELECT id FROM mat_stories WHERE mat_number=9902")).rows[0].id;
    const screenshotDir = "../../docs/screenshots"; await mkdir(screenshotDir, { recursive: true });
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.screenshot({ path: `${screenshotDir}/admin-desktop.png`, fullPage: true });
    await page.goto("/");
    await page.evaluate(() => document.fonts.ready);
    await expect(page.locator(".story-card")).toHaveCount(1);
    await page.screenshot({ path: `${screenshotDir}/stories-desktop.png`, fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: `${screenshotDir}/stories-mobile.png`, fullPage: true });
    await page.goto(`/stories/${storyId}`);
    const reaction = page.getByRole("button", { name: /이 이야기에 공감해요/ });
    await expect(reaction).toBeEnabled(); await reaction.click();
    await expect(page.getByRole("button", { name: /공감을 전했어요/ })).toBeDisabled();
    await page.reload(); await expect(page.getByRole("button", { name: /공감을 전했어요/ })).toBeDisabled();
    await page.screenshot({ path: `${screenshotDir}/story-mobile.png`, fullPage: true });
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
    const other = await browser.newContext();
    try {
      const otherPage = await other.newPage(); await otherPage.goto(`/stories/${storyId}`);
      await expect(otherPage.getByRole("button", { name: /이 이야기에 공감해요/ })).toBeEnabled();
    } finally { await other.close(); }
    await page.setViewportSize({ width: 390, height: 844 }); await page.goto("/about");
    await expect(page.getByText("3,000원", { exact: true })).toBeVisible();
    await expect(page.getByText("5,000원", { exact: true })).toBeVisible();
    await expect(page.getByRole("link", { name: /내 이야기 남기러 가기/ })).toHaveAttribute("href", "https://naver.me/Gjyqyq7s");
    await page.screenshot({ path: `${screenshotDir}/about-mobile.png`, fullPage: true });
    await page.goto("/admin"); await page.getByRole("button", { name: "수정·검토" }).click();
    await page.getByLabel("내용 검토 완료 · 웹에 공개").uncheck();
    await page.getByRole("button", { name: "비공개로 저장" }).click();
    await expect(page.getByText("비공개", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "로그아웃" }).click();
    await expect(page.getByRole("button", { name: "관리자 페이지로 이동" })).toBeVisible();
    await page.goto(`/stories/${storyId}`); await expect(page.getByRole("heading", { name: "아직 펼쳐지지 않은 이야기예요." })).toBeVisible();
    expect(errors).toEqual([]);
  } finally {
    if (storyId) await pool.query("DELETE FROM mat_stories WHERE id=$1", [storyId]);
    await pool.end();
  }
});

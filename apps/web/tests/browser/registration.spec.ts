import { test, expect } from "@playwright/test";
test("responsive introduction and form", async ({ page }) => {
  for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }, { width: 320, height: 740 }]) {
    await page.setViewportSize(viewport);
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toContainText("기억이 머물던 곳에");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.screenshot({ path: `test-results/landing-${viewport.width}.png`, fullPage: true });
  }
});
test("form validation, real submission, retries and network failure", async ({ page }) => {
  await page.goto("/#apply");
  const submit = page.getByRole("button", { name: "테스트 사전신청하기" });
  await submit.click();
  await expect(page.getByText("이름을 입력해주세요.", { exact: true })).toBeVisible();
  for (let attempt = 0; attempt < 2; attempt++) {
    await page.getByLabel("이름", { exact: false }).fill("브라우저 테스트");
    await page.getByLabel("휴대폰 번호").fill("010-0000-9876");
    await page.getByLabel("[필수] 개인정보 수집·이용에 동의합니다.").check();
    await submit.click();
    await expect(page.getByRole("heading", { name: "테스트 신청이 접수됐어요" })).toBeVisible();
    await page.reload();
  }
  await page.getByLabel("이름", { exact: false }).fill("오류 테스트");
  await page.getByLabel("휴대폰 번호").fill("010-0000-9877");
  await page.getByLabel("[필수] 개인정보 수집·이용에 동의합니다.").check();
  await page.route("**/api/registrations", (route) => route.abort());
  await submit.click();
  await expect(page.getByRole("alert").filter({ hasText: "접수 결과" })).toContainText("접수 결과를 확인하지 못했어요");
  await expect(page.getByLabel("휴대폰 번호")).toHaveValue("010-0000-9877");
});
test("API rejects invalid and cross-origin requests", async ({ request, baseURL }) => {
  const data = { name: "API 테스트", phone: "01000009999", consent: true, formVersion: 1 };
  expect((await request.post("/api/registrations", { data, headers: { origin: "https://untrusted.example" } })).status()).toBe(403);
  expect((await request.post("/api/registrations", { data: { ...data, consent: false }, headers: { origin: baseURL! } })).status()).toBe(422);
  expect((await request.post("/api/registrations", { data: { ...data, name: "a".repeat(5000) }, headers: { origin: baseURL! } })).status()).toBe(413);
  expect((await request.get("/api/registrations")).status()).toBe(405);
  expect((await request.get("/api/health")).status()).toBe(200);
});

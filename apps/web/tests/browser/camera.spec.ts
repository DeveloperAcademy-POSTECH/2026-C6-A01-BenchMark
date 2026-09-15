import { test, expect } from "@playwright/test";
test.use({ permissions: ["camera"], viewport: { width: 390, height: 844 }, launchOptions: {
  executablePath: process.env.CHROME_EXECUTABLE || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--enable-unsafe-swiftshader"],
} });
test("camera preview, controls, worker segmentation, capture and download without database", async ({ page }) => {
  const activity: { name: string; properties: unknown }[] = [];
  page.on("request", request => { if (new URL(request.url()).pathname === "/api/activity") activity.push(...request.postDataJSON().events); });
  const errors: string[] = []; page.on("pageerror", e => errors.push(e.message));
  const response = await page.goto("/camera");
  expect(response?.headers()["permissions-policy"]).toContain("camera=(self)");
  await page.getByRole("button", { name: "카메라 시작", exact: true }).click();
  const shutter = page.getByRole("button", { name: "사진 촬영", exact: true });
  await expect(shutter).toBeEnabled({ timeout: 20000 });
  await page.getByRole("button", { name: "둘 다 표시" }).click();
  await page.getByLabel("크기", { exact: true }).fill("0.5");
  await page.getByLabel("방향", { exact: false }).fill("90");
  await page.getByLabel("캐릭터를 사람 뒤에 배치").check();
  await expect(page.getByRole("status")).toContainText("인물 가림이 준비됐어요", { timeout: 30000 });
  await expect.poll(() => page.evaluate(() => {
    const c = document.querySelector("canvas")!; const data = c.getContext("2d")!.getImageData(0, 0, c.width, c.height).data;
    return data.some(v => v > 0);
  })).toBe(true);
  await page.screenshot({ path: test.info().outputPath("camera-preview.png"), fullPage: true });
  await shutter.click();
  await expect(page.getByAltText("캐릭터와 함께 촬영한 사진")).toBeVisible();
  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("link", { name: "사진 다운로드" }).click();
  const download = await downloadPromise; expect(download.suggestedFilename()).toBe("benchmark-photo.jpg");
  await page.getByRole("button", { name: "다시 촬영" }).click();
  await expect(shutter).toBeEnabled();
  await page.getByRole("button", { name: "카메라 전환" }).click(); await expect(shutter).toBeEnabled();
  await page.getByRole("button", { name: "카메라 끄기" }).click();
  await expect(page.getByRole("button", { name: "카메라 시작", exact: true })).toBeVisible();
  await expect.poll(() => activity.some(event => event.name === "photo_download_click"), { timeout: 10000 }).toBe(true);
  for (const name of ["camera_start_attempt", "camera_ready", "photo_capture_attempt", "photo_capture_success", "photo_download_click"]) expect(activity.some(event => event.name === name)).toBe(true);
  expect(activity.filter(event => event.name.startsWith("photo_")).every(event => JSON.stringify(event.properties) === "{}")).toBe(true);
  expect(errors).toEqual([]);
});
test("camera denial offers actionable retry", async ({ page }) => {
  await page.addInitScript(() => { navigator.mediaDevices.getUserMedia = async () => { throw new DOMException("Denied", "NotAllowedError"); }; });
  await page.goto("/camera"); await page.getByRole("button", { name: "카메라 시작", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("카메라 권한을 허용");
  await expect(page.getByRole("button", { name: "카메라 시작", exact: true })).toBeVisible();
});

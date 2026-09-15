import { test, expect } from "@playwright/test";

test("production excludes the develop-only character camera", async ({ page, request }) => {
  const response = await page.goto("/");
  expect(response?.headers()["permissions-policy"]).toContain("camera=()");
  await expect(page.locator('a[href^="/camera"]')).toHaveCount(0);
  await expect(page.getByText("캐릭터와 사진 찍기", { exact: true })).toHaveCount(0);
  for (const path of ["/camera", "/camera?from=00000000-0000-4000-8000-000000000001", "/models/postech.glb", "/mediapipe/wasm/vision_wasm_internal.wasm", "/draco/draco_decoder.wasm"]) {
    expect((await request.get(path)).status(), path).toBe(404);
  }
  await page.goto("/reserve");
  await expect(page.getByLabel("사진 추가", { exact: true })).toHaveCount(1);
  await expect(page.getByRole("radio", { name: "3,000원", exact: true })).toBeVisible();
  await expect(page.getByRole("radio", { name: "5,000원", exact: true })).toBeVisible();
});

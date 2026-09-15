import { test, expect } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import sharp from "sharp";

test("home redirects without caching and excludes the previous public story", async ({ page, request }) => {
  if (!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test")) throw new Error("Use the isolated test database only.");
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const ids = [randomUUID(), randomUUID(), randomUUID()];
  const photo = await sharp({ create: { width: 100, height: 100, channels: 3, background: "#e4dec4" } }).jpeg().toBuffer();
  const home = () => request.get("/", { maxRedirects: 0 });
  try {
    expect(Number((await pool.query("SELECT count(*) FROM mat_stories WHERE published AND payment_verified")).rows[0].count)).toBe(0);
    const empty = await home();
    expect(empty.status()).toBe(307);
    expect(empty.headers().location).toBe("/stories");
    await page.goto("/");
    await expect(page.locator(".empty-state")).toBeVisible();
    for (const [index, id] of ids.entries()) {
      await pool.query("INSERT INTO mat_stories(id,mat_number,mat_size,display_name,title,story,photo,payment_verified,published) VALUES($1,9924,'small','검증용','검증용 이야기','검증용 본문',$2,$3,$4)", [id, photo, index !== 2, index === 0]);
    }
    for (let i = 0; i < 3; i++) {
      const single = await home();
      expect(single.status()).toBe(307);
      expect(single.headers().location).toBe(`/stories/${ids[0]}`);
      expect(single.headers()["cache-control"]).toContain("no-store");
      expect(single.headers().vary).toContain("Cookie");
      expect(single.headers()["set-cookie"]).toContain("HttpOnly");
      expect(single.headers()["set-cookie"]).toContain("SameSite=lax");
    }
    await pool.query("UPDATE mat_stories SET published=true WHERE id=$1", [ids[1]]);
    let previous: string = ids[0];
    for (let i = 0; i < 8; i++) {
      const response = await home();
      const current = response.headers().location.split("/").pop()!;
      expect(ids.slice(0, 2)).toContain(current);
      expect(current).not.toBe(previous);
      previous = current;
    }
    const malformed = await request.get("/", { maxRedirects: 0, headers: { Cookie: "last-home-story=invalid" } });
    expect(malformed.status()).toBe(307);
    await page.goto("/");
    const selected = page.url();
    await expect(page.locator(".story-paper h1")).toHaveText("검증용 이야기");
    await page.reload();
    await expect(page).toHaveURL(selected);
    await page.goto("/");
    expect(page.url()).not.toBe(selected);
    const current = page.url();
    await page.getByRole("link", { name: "다른 자리의 이야기도 만나보기 →" }).click();
    await expect(page).toHaveURL("/stories");
    await page.getByRole("link", { name: "쉼, 펴 홈" }).click();
    expect(page.url()).not.toBe(current);
    await expect(page).toHaveURL(/\/stories\/[0-9a-f-]+$/);
    await pool.query("UPDATE mat_stories SET published=false WHERE id=ANY($1::uuid[])", [ids]);
    expect((await home()).headers().location).toBe("/stories");
  } finally {
    await pool.query("DELETE FROM mat_stories WHERE id=ANY($1::uuid[])", [ids]);
    await pool.end();
  }
});

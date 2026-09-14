import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests/browser", fullyParallel: false, workers: 1, timeout: 45000,
  use: { baseURL: process.env.TEST_BASE_URL || "http://127.0.0.1:4314", headless: true,
    launchOptions: { executablePath: process.env.CHROME_EXECUTABLE || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" } },
  reporter: "list",
});

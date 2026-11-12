import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests",
  timeout: 30000,
  use: {
    baseURL: "http://127.0.0.1:1420",
    viewport: { width: 1440, height: 980 },
    launchOptions: process.env.CAMPUSGO_TEST_BROWSER
      ? { executablePath: process.env.CAMPUSGO_TEST_BROWSER }
      : {},
  },
  webServer: {
    command: "npm run dev",
    url: "http://127.0.0.1:1420",
    reuseExistingServer: !process.env.CI,
  },
  workers: 1,
});

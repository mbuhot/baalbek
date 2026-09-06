import { homedir } from "node:os";
import { join } from "node:path";
import { defineConfig, devices } from "@playwright/test";
import { BASE_URL } from "./stack";

/**
 * Playwright against the containerised `MIX_ENV=prod` release (PLAN.md Stage 9).
 *
 * `globalSetup` owns the stack; nothing here starts an application from source,
 * and no test may stub the API. Setting `E2E_BASE_URL` runs the same suite
 * against an environment someone else already runs — `globalSetup` then starts
 * no containers, checks no images, and tears nothing down.
 */
export default defineConfig({
  testDir: "./tests",
  // Off the virtiofs-mounted repo: Playwright deletes this directory at the
  // start of a run and its workers immediately re-create it, which fails with
  // ENOTDIR on that mount. Same workaround as CARGO_TARGET_DIR in
  // pricing/moon.yml and Gradle's build dir in mobile/.
  outputDir: process.env.PLAYWRIGHT_OUTPUT_DIR ?? join(homedir(), ".cache", "baalbek-playwright", "test-results"),
  globalSetup: "./global-setup.ts",
  globalTeardown: "./global-teardown.ts",
  // The stack is one shared database, so the suite writes with unique ids
  // rather than serialising; see tests/seed.ts.
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  workers: process.env.CI ? 2 : undefined,
  retries: 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : [["list"]],
  timeout: 30_000,
  expect: { timeout: 10_000 },
  use: {
    baseURL: BASE_URL,
    trace: "retain-on-failure",
    // The PWA registers a Workbox service worker; a cached shell would let a
    // test pass against assets the stack is no longer serving.
    serviceWorkers: "block",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});

import { expect, test } from "@playwright/test";

/** The PWA shell as built by `web:build`, not as served by a dev server. */

test("serves the production bundle and the web manifest", {
  tag: ["@capability/release-assurance", "@capability/field-app-delivery"],
}, async ({ page, request }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "Baalbek Dispatch" })).toBeVisible();

  // Vite's production output is hashed; a dev server serves /src/main.tsx instead.
  const scripts = await page.locator("script[src]").evaluateAll((nodes) =>
    nodes.map((node) => node.getAttribute("src") ?? ""),
  );
  expect(scripts.some((src) => /^\/assets\/.+-[A-Za-z0-9_-]{8,}\.js$/.test(src))).toBe(true);

  const manifest = await request.get("/manifest.webmanifest");
  expect(manifest.status()).toBe(200);
  expect(await manifest.json()).toMatchObject({ name: "Baalbek Dispatch" });
});

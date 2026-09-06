/// <reference types="vitest/config" />
import { defineConfig } from "vite";
import preact from "@preact/preset-vite";
import { VitePWA } from "vite-plugin-pwa";

/** Vite config for the dispatch-board PWA: Preact + a minimal installable-shell service worker. */
export default defineConfig({
  plugins: [
    preact(),
    VitePWA({
      registerType: "autoUpdate",
      manifest: {
        name: "Baalbek Dispatch",
        short_name: "Dispatch",
        description: "Field-service dispatch board and technician work queue.",
        start_url: "/",
        display: "standalone",
        background_color: "#111827",
        theme_color: "#111827",
        icons: [
          {
            src: "icon.svg",
            sizes: "any",
            type: "image/svg+xml",
            purpose: "any maskable",
          },
        ],
      },
    }),
  ],
  // The app calls its API on its own origin, so the dev server forwards /api to `server`.
  server: {
    proxy: { "/api": "http://localhost:4004" },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    globals: false,
  },
});

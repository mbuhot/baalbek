/// <reference types="vitest/config" />
import { defineConfig } from "vite";

/** Vite config for the explorer: a static site with relative asset URLs, so `dist` serves from any path. */
export default defineConfig({
  base: "./",
  build: {
    // Cytoscape is ~490 kB on its own; see spec/decisions/adr-0002-*.
    chunkSizeWarningLimit: 2048,
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});

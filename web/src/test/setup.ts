import "@testing-library/jest-dom/vitest";
import { afterEach, vi } from "vitest";
import { cleanup } from "@testing-library/preact";

/** vitest global setup: jest-dom matchers, Preact Testing Library cleanup, and per-test fetch-stub teardown. */
afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
});

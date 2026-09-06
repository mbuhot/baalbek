import { describe, expect, it } from "vitest";
import { resolveApiBaseUrl } from "./api";

const sources = {
  runtime: undefined,
  buildTime: undefined,
  origin: "https://dispatch.example",
  isNativeApp: false,
};

describe("resolveApiBaseUrl", () => {
  it("defaults to the origin serving the app", () => {
    expect(resolveApiBaseUrl(sources)).toBe("https://dispatch.example/api/json/core");
  });

  it("prefers deploy-time configuration over the serving origin", () => {
    const url = resolveApiBaseUrl({ ...sources, runtime: "https://api.example/api/json/core" });
    expect(url).toBe("https://api.example/api/json/core");
  });

  it("prefers deploy-time configuration over the build-time override", () => {
    const url = resolveApiBaseUrl({
      ...sources,
      runtime: "https://api.example/api/json/core",
      buildTime: "https://baked.example/api/json/core",
    });
    expect(url).toBe("https://api.example/api/json/core");
  });

  it("ignores an empty deploy-time value, which is what the browser bundle ships", () => {
    expect(resolveApiBaseUrl({ ...sources, runtime: "  " })).toBe("https://dispatch.example/api/json/core");
  });

  // The packaged app's own origin is the device, so falling back to it would
  // make the app fetch its own bundle — the failure this guard converts.
  it("refuses to guess for a packaged app with no configuration", () => {
    expect(() => resolveApiBaseUrl({ ...sources, origin: "capacitor://localhost", isNativeApp: true })).toThrow(
      /must set globalThis.__API_BASE_URL__/,
    );
  });

  it("uses the configured URL for a packaged app", () => {
    const url = resolveApiBaseUrl({
      ...sources,
      runtime: "http://10.0.2.2:4004/api/json/core",
      origin: "http://localhost",
      isNativeApp: true,
    });
    expect(url).toBe("http://10.0.2.2:4004/api/json/core");
  });
});

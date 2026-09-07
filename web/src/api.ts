import { createCoreApiClient } from "core-api-client";

/** Where this copy of the app finds its API, and everything that can decide it. */
export interface ApiBaseUrlSources {
  /** `globalThis.__API_BASE_URL__`, set by `api-config.js` — deploy-time configuration. */
  runtime: string | undefined;
  /** `VITE_API_BASE_URL`, baked in by the Vite build. */
  buildTime: string | undefined;
  /** The origin serving the app. */
  origin: string;
  /** True inside a packaged Capacitor WebView, whose origin is the device itself. */
  isNativeApp: boolean;
}

/**
 * Resolves the API base URL: deploy-time configuration, then the build-time
 * override, then the origin serving the app.
 *
 * A packaged app has no usable origin — its own is the device — so it must be
 * configured. This raises instead, rather than letting the app request its own
 * bundle and render an empty board.
 */
export function resolveApiBaseUrl({ runtime, buildTime, origin, isNativeApp }: ApiBaseUrlSources): string {
  const configured = (runtime ?? "").trim() || (buildTime ?? "").trim();
  if (configured !== "") return configured;

  if (isNativeApp) {
    throw new Error(
      "No API base URL configured: a packaged app must set globalThis.__API_BASE_URL__ (mobile/scripts/stamp-api-config.sh does).",
    );
  }

  return `${origin}/api/json/core`;
}

interface ApiGlobals {
  __API_BASE_URL__?: string;
  Capacitor?: { isNativePlatform?: () => boolean };
}

const globals = globalThis as unknown as ApiGlobals;

/** Base URL of `server`'s core JSON:API for this deployment. */
export const API_BASE_URL = resolveApiBaseUrl({
  runtime: globals.__API_BASE_URL__,
  buildTime: import.meta.env.VITE_API_BASE_URL,
  origin: globalThis.location.origin,
  isNativeApp: globals.Capacitor?.isNativePlatform?.() ?? false,
});

/** The app's single typed client instance, bound to `API_BASE_URL`. */
export const coreApi = createCoreApiClient(API_BASE_URL);

import { createCoreApiClient } from "core-api-client";

/** Base URL of `server`'s core JSON:API, overridable per environment via `VITE_API_BASE_URL`. */
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:4004/api/json/core";

/** The app's single typed client instance, bound to `API_BASE_URL`. */
export const coreApi = createCoreApiClient(API_BASE_URL);

/** Typed fetch client for `core`'s JSON:API, generated from `server`'s OpenAPI spec. */
import createClient from "openapi-fetch";
import type { paths, components } from "./generated/schema";

export type { paths, components };

/** A JSON:API resource object for one of `core`'s four resources. */
export type Customer = components["schemas"]["customer"];
export type Site = components["schemas"]["site"];
export type Job = components["schemas"]["job"];
export type WorkOrder = components["schemas"]["work_order"];

/** Creates a typed client bound to `server`'s core JSON:API (mounted under `/api/json/core`). */
export function createCoreApiClient(baseUrl: string) {
  return createClient<paths>({
    baseUrl,
    // Reads `globalThis.fetch` per call, not once at client-creation time, so
    // tests can stub it (e.g. `vi.stubGlobal("fetch", ...)`) after this client
    // already exists — see web/src/test/mockFetch.ts.
    fetch: (...args: Parameters<typeof fetch>) => globalThis.fetch(...args),
  });
}

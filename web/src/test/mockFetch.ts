import { vi } from "vitest";

interface JsonRoute {
  path: string;
  status?: number;
  body: unknown;
}

/** Stubs `globalThis.fetch` to serve canned JSON:API responses by URL pathname (this project's HTTP-mock strategy — see web/README.md). */
export function mockJsonRoutes(routes: JsonRoute[]): void {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(typeof input === "string" || input instanceof URL ? input : input.url);
      const route = routes.find((candidate) => url.pathname === candidate.path);
      if (!route) {
        throw new Error(`Unhandled fetch to ${url.pathname} in test`);
      }
      return new Response(JSON.stringify(route.body), {
        status: route.status ?? 200,
        headers: { "content-type": "application/vnd.api+json" },
      });
    }),
  );
}

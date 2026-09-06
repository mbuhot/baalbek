# web

**Language:** TypeScript

**Purpose:** PWA: dispatch board + technician view.

## Stage 6 (this stage)

A [Preact](https://preactjs.com) + [Vite](https://vite.dev) PWA, chosen over
React/Solid for a small dependency footprint in a reference project. All
data comes from `server`'s core JSON:API through the generated
[`core-api-client`](../core-api-client) — no hand-typed API shapes.

- **Dispatch board** (`src/components/DispatchBoard.tsx`): lists jobs,
  joined client-side to their site and customer (the JSON:API declares no
  relationships between these resources, so the join happens in
  `src/hooks/useDispatchBoard.ts` by matching `site_id`/`customer_id`).
- **Technician view** (`src/components/TechnicianView.tsx`): **a
  documented simplification.** `identity` (technicians/dispatchers) isn't
  exposed over HTTP yet (see `server/README.md`), so there's no real
  per-technician assignment to show. This view lists all open work orders
  instead — a genuine "work queue" shape, open/in-progress first, joined
  to each work order's job — but it is **not** filtered to one technician.
  It stands in for that view honestly rather than fabricating technician
  data; swap in real filtering once `identity` grows an HTTP surface.
- **PWA shell**: a real web manifest and a generated service worker via
  [`vite-plugin-pwa`](https://vite-pwa-org.netlify.app) (`generateSW`
  mode) — installable, offline-capable shell. No custom caching strategy
  beyond Workbox's precache defaults; that's enough for this reference
  project's scope.

### Testing scope

Stage 9 (`e2e`, Playwright) is the end-to-end layer against a live
`server`. This package's tests (`vitest` + `@testing-library/preact`)
stay one level down: they render real components against **fixture data
typed from the generated client** (`src/test/fixtures.ts` imports
`Customer`/`Site`/`Job`/`WorkOrder` from `core-api-client`, so a schema
change that drops or renames a field fails these tests' types too), with
`globalThis.fetch` stubbed per test (`src/test/mockFetch.ts`) rather than
hitting a real server. This proves the fetch → join → render path without
needing Postgres or a running Phoenix app in this package's own test run.

`msw` was tried first for HTTP mocking but its Node request interceptor
didn't intercept fetch calls in this sandbox (Node 26); a small
`vi.stubGlobal("fetch", ...)` helper replaced it — see
`src/test/mockFetch.ts`'s header comment. `core-api-client`'s client also
re-reads `globalThis.fetch` per call (not once at client-creation time)
specifically so this stubbing works after the client singleton already
exists.

### Module-boundary lint

seed.md §3 requires module-boundary enforcement to be lint-level with CI
blocking it, not merely advisory. `eslint.config.js`'s `no-restricted-imports`
rule blocks any import reaching past `core-api-client`'s package root into
its internals (e.g. `core-api-client/src/generated/*`) — this package may
only import the public `core-api-client` entry point. `lint` is its own
Moon task (independently runnable), and `test` depends on it, so the Stage 6
gate (`moon run web:test`) enforces it too.

## Stage 8

`spec/mocks/` holds dated snapshots of what the dispatch board and technician
view were meant to be when they were built, and `spec/mocks/README.md`
explains why they are never updated. `spec/decisions/` records why `web:test`
depends on `web:build`.

No `spec/features/` here: Gherkin in this repo is wired to ExUnit, and the
UI's acceptance layer is the Playwright suite in `e2e` (Stage 9).

## Local setup

```bash
# from repo root
moon run core-api-client:build   # generates the client from server's OpenAPI spec
cd web
pnpm install
pnpm run dev       # http://localhost:5173, proxies /api to `server` on :4004
pnpm run lint
pnpm run test
pnpm run build
```

Or via Moon: `moon run web:test` / `moon run web:build` from the repo root
(both depend on `core-api-client:build`, which depends on `server:openapi`;
`test` also depends on `lint`).

### Which API this app talks to

`src/api.ts`'s `resolveApiBaseUrl` decides, in this order:

1. **`globalThis.__API_BASE_URL__`** — deploy-time configuration, set by
   `public/api-config.js`, a plain script the built `index.html` loads before
   the bundle. It ships empty, and is rewritten per environment.
2. **`VITE_API_BASE_URL`** — a build-time override, for local experiments.
3. **The origin serving the app**, `<origin>/api/json/core`.

One `dist` therefore serves every consumer, and there is **no CORS
configuration anywhere in this repository** — not in `server`, not in nginx.
That is a property of the three deployments, not an oversight:

| Consumer | Origin of the app | How it reaches the API |
|---|---|---|
| Browser | wherever `baalbek-web` is served | same origin, `/api` proxied to `server` by nginx |
| `e2e` | that same image on `localhost:4014` | same proxy |
| `mobile` | the device (`capacitor://localhost`, `http://localhost`) | `CapacitorHttp` makes **native** requests, which the WebView never applies CORS to |

The one case that would need CORS is a browser PWA deployed on a *different*
origin from the API — a CDN in front of the bundle, say. `nginx.conf.template`
in this project is where it would go, since that is the tier that would then be
serving a cross-origin app; `server` should stay free of it.

`Dockerfile` is what makes the same-origin default true: `moon run web:image`
builds `baalbek-web:latest`, nginx serving `dist` with `/api` reverse-proxied to
`SERVER_ORIGIN` (default `http://server:4004`, substituted into the config by
nginx's own entrypoint at container start). It copies the `dist` that `build`
produces rather than re-building it, so the bundle it serves is the same one
`mobile` embeds. The Stage 9 e2e stack composes that image and defines no
serving configuration of its own; the dev server proxies `/api` to `:4004` for
the same reason. See
`../e2e/spec/decisions/adr-0001-dockerized-e2e-stack.md`.

A packaged app has no usable origin of its own, so rule 3 cannot apply to it:
`mobile/scripts/stamp-api-config.sh` rewrites `api-config.js` inside the synced
native bundle (`MOBILE_API_BASE_URL`, defaulting to the host machine as seen
from an emulator). `resolveApiBaseUrl` raises inside a Capacitor WebView with
nothing configured, rather than letting the app request its own bundle and
render an empty board — `src/api.test.ts` covers that and every other rule.

### Linking to `core-api-client`

`web` and `core-api-client` are pnpm workspace members (root
`pnpm-workspace.yaml`); `web/package.json` depends on it via
`workspace:*`, and `pnpm install` symlinks it into `web/node_modules`.
There is no root `package.json` — pnpm only needs `pnpm-workspace.yaml` to
detect the workspace root (verified empirically: `pnpm install`,
`pnpm --filter web run <script>`, and every Moon task work with no
`package.json` at the repo root). TypeScript project references
(`web/tsconfig.json`'s `references`) give the real build-time edge:
`web`'s `tsc -b` fails if `core-api-client`'s public types change
incompatibly. Both tsconfigs extend the shared, non-executable
`config/tsconfig.base.json` — a `config/` directory, not a package, holding
only options common to every TS package here.

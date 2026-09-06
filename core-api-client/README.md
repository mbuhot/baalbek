# core-api-client

**Language:** TypeScript (generated)

**Purpose:** Generated from `core`'s OpenAPI spec. Build-time edge.

## Stage 6 (this stage)

The only generated artifact is `src/generated/schema.d.ts` — produced by
[`openapi-typescript`](https://openapi-ts.dev) from `server/priv/static/openapi.json`
(gitignored, same as the spec it's generated from). `src/index.ts` is a
thin, hand-written wrapper: it creates an [`openapi-fetch`](https://openapi-ts.dev/openapi-fetch/)
client typed against those generated types, and re-exports the JSON:API
resource-object types (`Customer`, `Site`, `Job`, `WorkOrder`) that `web`
renders. Nothing here hand-declares the API shape — a breaking change to
`server`'s JSON:API surface changes the generated types, and `web`'s
`tsc` build fails instead of drifting silently (seed.md §6).

`moon.yml`'s `build` task regenerates the schema from `server`'s published
spec and type-checks this package against it; `dependsOn: [server]` plus a
task `deps` on `server:openapi`, which declares the spec file as its
`outputs`, make a `server` API change invalidate this task's cache — and,
through `server:openapi`'s own deps, a change in any Elixir app, the Rust
crate or the Gleam package behind it
(`../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md`).

## Usage

```ts
import { createCoreApiClient } from "core-api-client";

const api = createCoreApiClient("http://localhost:4004/api/json/core");
const { data, error } = await api.GET("/jobs", {});
```

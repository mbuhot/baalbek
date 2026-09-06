# ADR-0001: `web:test` depends on `web:build`, because vitest does not type-check

**Status:** Accepted
**Date:** 2026-09-06
**Stage:** 6

## Context

seed.md §6 makes a specific promise about the generated-client edge: "a
breaking API change fails the consumer's build instead of surfacing at
runtime". In this repo the mechanism is TypeScript — `core-api-client`
publishes types generated from `server`'s OpenAPI spec, `web` imports them,
and `tsc` is what notices when a field is renamed away.

`web`'s test runner is vitest, which transforms TypeScript with esbuild.
esbuild strips types; it never checks them. So `pnpm run test` passes against
a breaking API change: the code compiles to JavaScript that reads a field
which no longer exists, the fixtures assert on it, and nothing objects until
runtime.

`moon check --all` runs `web:build` and would catch it. But PLAN.md's Stage 6
gate is `moon run server:test web:test`, and a guarantee that only holds
under a different command than the one the gate names is not a guarantee.

## Decision

`web:test` declares `deps: ["build", "lint", "core-api-client:build"]`.
`build` runs `tsc -b`, so running the gate command alone enforces real type
checking as well as the module-boundary lint.

## Consequences accepted

- **`web:test` is slower than a test task looks.** It produces a production
  Vite build first. Moon caches it, so the cost lands on cold runs and on
  runs where `web` or `core-api-client` genuinely changed.
- **The dependency reads as odd.** Tests depending on a production build
  inverts the usual order, which is why this ADR exists rather than a comment
  alone.
- **The lint dependency rides along for the same reason.** seed.md §3 says
  module-boundary enforcement in this ecosystem is advisory unless CI blocks
  it; making `test` depend on `lint` is what blocks it under the gate command.

## Alternatives considered

**`vitest --typecheck`.** vitest can run `tsc` alongside the suite, but it
type-checks test files and their imports, not the project as `tsc -b` sees
it, and it duplicates configuration that `tsconfig.json` already holds. The
build task is already the authoritative type check; pointing the gate at it
is less machinery, not more.

**Fold `tsc --noEmit` into `web:test`'s command.** Would work, and would run
the type check twice per `moon check --all` (once here, once in `build`) with
no cache sharing between them, because it would be part of a different task's
command rather than a task in its own right.

**Change the gate to `moon check --all`.** Rejected as the wrong direction:
the point is that a named gate command should enforce what it claims, not
that gates should be broadened until they do.

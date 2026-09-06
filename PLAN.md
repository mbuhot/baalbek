# Implementation Plan

Derived from `seed.md` plus session decisions. Scope is **State C only** — the modular monolith. The estate and migration narrative (seed §10) is out of scope.

## Decisions taken this session

| Question | Decision |
|---|---|
| Domain | Field service / job dispatch |
| Demo states | State C only |
| Moon Elixir plugin (§2) | Build it |
| Gleam (§11) | One event-sourced component: technician timeline / availability |
| Architecture explorer (§9) | In scope |
| Gherkin acceptance specs (§7.5) | In scope |
| Visual regression (§7.6) | Out of scope |
| Mobile | Capacitor wrapper over the PWA, Android + iOS builds as tier-0 Moon tasks |
| Audience | Reusable Alembic reference project, no deadline |
| Repo | `git init` in place; `seed.md` stays at root |
| Toolchain | proto owns every tool version; sandboxed container |

## Toolchain: proto owns everything

Verified against moonrepo/plugins:

- First-party proto tools: node, pnpm, bun, deno, go, rust, python, ruby, java, swift, zig, moon, proto.
- **No** first-party Elixir, Erlang, or Gleam tool plugin.
- proto ships a built-in **asdf backend**, invoked as `asdf:<id>`, which resolves the asdf plugin index and runs its scripts.

Root `.prototools`:

```toml
moon           = "2"
node           = "26.7.0"
pnpm           = "11.9.0"
rust           = "stable"
"asdf:erlang"  = "28.5"
"asdf:elixir"  = "1.20.2"
"asdf:gleam"   = "1.13"
```

Consequences:

- Task hashes include toolchain versions, satisfying the hermeticity posture in §7.
- Erlang builds from source under the asdf backend; the container image caches the built OTP layer.
- The host's asdf installation is bypassed. The sandbox has no preinstalled language runtime.

`.moon/toolchains.yml` enables `node`, `pnpm`, `typescript`, `rust`, `system`, plus the custom Elixir toolchain (§ Stage 11) once built. Every toolchain sets `versionFromPrototools: true`.

## Sandbox

A `Dockerfile` + `.devcontainer/devcontainer.json` producing an image with:

- proto, and nothing else language-related
- build deps for OTP from source and for Rustler NIFs
- Postgres 17 as a compose service
- `proto install` run at image build to warm the layer

Same image runs CI, so an under-declared task input fails immediately.

## Component inventory

| Project | Language | Owns | Notes |
|---|---|---|---|
| `core` | Elixir / Ash | schema `core` | Jobs, customers, sites, work orders. Publishes OpenAPI. |
| `identity` | Elixir / Ash | schema `identity` | Technicians, dispatchers, auth. |
| `billing` | Elixir / Ash | schema `billing` | Invoices raised from completed jobs. |
| `timeline` | Gleam | schema `timeline` | Event-sourced technician shift / travel / on-site events; availability projections. |
| `timeline_facade` | Elixir | — | Sole caller of the Gleam modules; `boundary`-enforced. |
| `pricing` | Rust crate | — | Quote computation: travel + labour + parts. `cargo test`. |
| `pricing_native` | Elixir | — | Rustler NIF facade; sole referencer of the NIF module. |
| `server` | Elixir / Phoenix | — | Release assembly; HTTP surface; depends on all domain apps. |
| `web` | TypeScript | — | PWA: dispatch board + technician view. |
| `core-api-client` | TypeScript (generated) | — | From `core`'s OpenAPI spec. Build-time edge. |
| `mobile` | Capacitor | — | Android (Gradle) + iOS (xcodebuild) as tier-0 system tasks. |
| `e2e` | Playwright | — | Depends on `server` + `web` builds. |
| `explorer` | TypeScript | — | Static site from project-graph JSON + git stats + `capabilities.yml`. |
| `moon-elixir-plugin` | Rust → WASM | — | Mix path-dep inference. |

### Two facades, one pattern

`pricing` (Rust) and `timeline` (Gleam) both sit outside Mix's dependency graph. Each gets a thin Elixir facade app, and each cross-language edge is declared explicitly in `moon.yml` as `dependsOn`. This is what makes a Rust or Gleam change invalidate the Elixir suites. `boundary` enforces that no other app reaches past the facade.

## Data layer

- One Postgres database, one schema per owning component.
- One database role per component, granted only on its own schema.
- One Ecto Repo per Elixir component, connecting as that component's role. Small pools.
- The Gleam component connects with `pog` as the `timeline` role.
- Migrations are per-component Moon tasks.

Event sourcing in `timeline`: append-only event table plus projection tables rebuilt from the log. Availability queries read projections.

## Stages

Each stage ends green on the gates named. A passing gate is not re-run.

| # | Stage | Gate |
|---|---|---|
| 0 | Sandbox image, proto config, `git init`, repo skeleton | `proto install`, `moon --version` |
| 1 | Moon workspace: `.moon/workspace.yml`, `.moon/toolchains.yml`, project stubs, `dependsOn` drift-check script | `moon check --all` |
| 2 | `core` — Ash resources, schema + role, `boundary`, ExUnit | `moon run core:test` |
| 3 | `identity`, `billing` — resources, schemas, roles, per-component Repos | `moon run identity:test billing:test` |
| 4 | `pricing` crate + `pricing_native` NIF facade + declared cross-language edge | `moon run pricing:test pricing_native:test` |
| 5 | `timeline` (Gleam, event-sourced) + `timeline_facade` | `moon run timeline:test timeline_facade:test` |
| 6 | `server` release, OpenAPI generated from Ash, `core-api-client` generated, `web` PWA consumes it | `moon run server:test web:test` |
| 7 | `mobile` — Capacitor wrapper, Android + iOS system tasks | `moon run mobile:build` |
| 8 | `spec/` per component: `features/`, `mocks/`, `decisions/`; Gherkin wired to ExUnit; path-based within-app test selection | `moon run :test` |
| 9 | `e2e` Playwright against the built server + PWA | `moon run e2e:test` |
| 10 | `explorer` static site | `moon run explorer:build` |
| 11 | `moon-elixir-plugin` — Rust→WASM, parses `mix.exs` path deps, replaces the drift-check | `moon run moon-elixir-plugin:test`, then `moon check --all` |
| 12 | CI in the sandbox image, `moon ci`, README | full `moon ci` |

Stages 2–5 touch disjoint directories and can run in parallel once stage 1 lands. Stages 6–7 are sequential on 2–5. Stages 10 and 11 are independent of 6–9.

## Test selection

| Layer | Mechanism |
|---|---|
| Cross-project | `moon ci` affected-detection over declared inputs |
| Within Elixir app | Mix alias driven by `git diff`, mapping `lib/<area>` to `test/<area>` |
| Acceptance | Gherkin features in `spec/features/`, executed by ExUnit |
| End-to-end | Playwright task depending on server + web builds; full run on main |

`boundary` cannot see the test tree — it hooks the compiler tracer and ExUnit files are runtime scripts. Path convention carries the within-app mapping, checked by a Moon task.

## Open risks

| Risk | Handling |
|---|---|
| Gleam ↔ Elixir build integration on the BEAM | Gleam compiles to Erlang `.beam` output consumed by the facade app; the edge is a declared Moon `dependsOn`. Settle the exact mechanism in stage 5 and record it as an ADR. |
| Erlang from source under the asdf backend is slow | Cached container layer; version pinned in `.prototools`. |
| Moon Elixir WASM plugin is unproven work | Drift-check script (stage 1) holds the property until stage 11 lands. |
| openapi-generator Elixir output quality | Only the TypeScript client is generated. |
| iOS builds need macOS | `mobile:build-ios` is a system task, excluded from container CI. |

## Deferred

Schema merging / entity reconciliation across components (seed §5). Out of scope for the structure.

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

### Adding OS packages after the fact

`proto install` compiles Erlang/OTP from source, and it sits below the image's apt layer — so extending that existing package list invalidates the OTP build and forces a full recompile. Worse, the dependency chain `e2e:test` → `server:image` → `root:sandbox-image` would drag that recompile into the e2e gate.

So new OS packages go in **their own layer, appended after `proto install`**, leaving the OTP layer's cache intact. That trades a tidy single package list for a build that stays cheap. Consolidating the layers is a deliberate cleanup step for later, done once the package set has settled — not something to do incrementally, since each consolidation pays the OTP rebuild.

First case: Playwright's browser libraries (`libglib-2.0.so.0` and friends), needed because Stage 9's suite drives a browser *from the sandbox* against the composed release stack. Until they are in the image, `e2e:test` passes only where someone has run `npx playwright install-deps` by hand — the "green locally, red on a fresh machine" shape this repo keeps catching.

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

### Boundary enforcement, in-app and cross-app

Added mid-build (before Stage 3), applying retroactively to `core` (Stage 2) as a fast-follow:

- **Ash apps** (`core`, `identity`, `billing`, and any future Ash-domain app) use [`ash_boundary`](https://github.com/mbuhot/ash_boundary) instead of a hand-rolled `use Boundary` on a plain module. It's a Spark DSL extension on `Ash.Domain` that derives the `boundary` declaration from the domain DSL itself: `exports` automatically becomes the domain module plus every resource with at least one domain-level `define` (code interface) — so the public surface tracks the domain instead of being hand-maintained. The underlying `boundary` compiler (`compilers: [:boundary] ++ Mix.compilers()` — order still matters, per Stage 2's caught bug) still does the actual enforcement.
- **Non-Ash facade apps** (`pricing_native`, `timeline_facade`) keep a hand-written `use Boundary` — `ash_boundary` doesn't apply where there's no Ash Domain.
- **Cross-*app* enforcement is a real `boundary` feature**, not just in-app: a dependent poncho app can set `boundary: [default: [check: [apps: [:some_dep]]]]` in its own `mix.exs`, and `boundary` will then check that app's calls into `:some_dep`'s modules against whatever `deps`/`exports` `some_dep` itself declared (hand-written or `ash_boundary`-derived). This is the mechanism for enforcing that, e.g., `server` (Stage 6) can only reach each domain app's declared public interface once it takes a real Mix path dependency on it — not a theoretical concern, since `boundary`'s own docs document exactly this ("Restricting usage of external apps"). Not exercised yet in Stages 3–5, since none of those apps take a Mix path dependency on another sibling app yet; becomes real and testable starting Stage 6.

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
| 6 | `server` HTTP surface, OpenAPI generated from Ash, `core-api-client` generated, `web` PWA consumes it | `moon run server:test web:test` |
| 6c | `server` release assembly + Gleam-in-release packaging (see below) | release boots and serves, with `timeline_facade` working |
| 7 | `mobile` — Capacitor wrapper, Android + iOS system tasks | `moon run mobile:build` |
| 8 | `spec/` per component: `features/`, `mocks/`, `decisions/`; Gherkin wired to ExUnit; path-based within-app test selection | `moon run :test` |
| 9 | `e2e` Playwright against the **dockerized** release stack, not a dev server (see below) | `moon run e2e:test` |
| 10 | `explorer` static site | `moon run explorer:build` |
| 11 | `moon-elixir-plugin` — Rust→WASM, parses `mix.exs` path deps, replaces the drift-check | `moon run moon-elixir-plugin:test`, then `moon ci`, then one `moon check --all` |
| 12 | CI in the sandbox image, `moon ci`, README | full `moon ci` |

Stages 2–5 touch disjoint directories and can run in parallel once stage 1 lands. Stages 6–7 are sequential on 2–5. Stages 10 and 11 are independent of 6–9.

### Capabilities: central vocabulary, local claims

seed.md §9 makes `capabilities.yml` the explorer's one hand-maintained input. Split it in two, because the mapping and the vocabulary have different owners.

- **`explorer/capabilities.yml` holds the vocabulary only** — id, name, description per capability. This is the artefact a CTO reads, and keeping it in one file is what makes seed.md's "a dozen capabilities, not hundreds" checkable at a glance.
- **Each project claims its own capabilities in its `moon.yml`**, as project-level tags. A component's capability claim is metadata about that component, and belongs with it for the same reason seed.md §8 puts a component's `spec/` inside the component. It also removes the cross-project edit that adding a component otherwise required, and it is queryable — `moon query projects --tags`.

`explorer:generate` joins the two and fails when a project claims nothing, or claims a capability the vocabulary doesn't define. Failing closed is the property that keeps the map honest; a central mapping file that nobody is forced to update is the failure mode this avoids.

**e2e specs claim capabilities too**, using the same vocabulary — Playwright tags on each test. That makes the vocabulary span all three of what a capability *is*, which components *serve* it, and which journeys *prove* it, and it lets a capability's e2e coverage be run on demand (`--grep`) rather than only as an undifferentiated suite.

The explorer must read those tags from `playwright test --list --reporter=json`, never by parsing spec files itself. Playwright owns that parser; re-implementing it invites the same drift as re-implementing Moon's hashing rule, where a wrong answer is worse than none because the tool reports confidently either way.

Two rules, deliberately asymmetric: a spec tagging a capability the vocabulary doesn't define **fails** the build, because that is a typo or a rename nobody propagated. A capability with no e2e coverage **is reported, not failed** — it is exactly the "where to invest next" signal seed.md §9 asks the zoomed-out view to carry, and blocking on it would only teach people to add a hollow spec.

Spellings as implemented: `capability/<id>` as a moon project tag (moon rejects a colon in a tag id; a slash is legal and unambiguous), `@capability/<id>` as a Playwright tag, and `platform` as the moon tag a project without a business capability carries. `explorer/spec/decisions/adr-0003-capabilities-are-a-vocabulary-with-local-claims.md` records the full rule set and what was rejected.

### Which gate to run, and when

`moon check --all` is a blunt instrument and was over-used early on. It runs every build and test task in the workspace unconditionally, ignores `runInCI`, and has no affected detection — so as the workspace grew it came to demand a Docker daemon, a free port, browser binaries, and OS libraries the sandbox image doesn't carry, all to answer "does this still hang together". It was also being run alongside `moon run :test`, which is a strict subset of it.

The routine gates are:

- **The stage's own gate** (`moon run <project>:test`) — proves the stage did what it claims.
- **`moon ci`** — proves nothing else regressed. Affected-only against a base ref, respects `runInCI` (so the macOS-only iOS task drops out without special-casing), continues past the first failure, and is *what CI actually runs*, which makes it the honest predictor. This is seed.md §1's described mechanism.
- **`moon check --all`** — only for a deliberate full sweep, not as a reflex. Stage 11 keeps one, because a change to how the project graph is inferred is exactly where forcing every task once is worth it.

### Stage 6c: release assembly, and why the Gleam edge needs it

Added mid-build, after Stage 6 shipped the HTTP surface but not the "release assembly" half of `server`'s inventory row.

`timeline_facade/mix.exs` loads `timeline`'s compiled Gleam output by calling `Code.prepend_path/1` at the **top level of `mix.exs`**, outside any module — it runs when Mix evaluates the project file. A `mix release` has no `mix.exs`, no Mix, and never evaluates that file; the boot script only knows what was baked in at assembly time. Worse, `timeline`'s BEAM output lives in `timeline/build/dev/erlang/*/ebin`, which `mix release` has no reason to traverse because `:timeline` is not a declared Mix dependency nor in `extra_applications`. So a release would not merely fail to prepend the path — it would not bundle the Gleam code at all.

This is the classic passes-tests-fails-in-production shape, currently latent only because nothing builds a release yet. `prune_code_paths: false` in that same file is the tell: it exists to stop Mix pruning a path Mix was never told about.

Stage 6c closes both gaps together: real `releases:` config for `server` (plus the release Dockerfile the Sandbox section implies), and packaging `timeline`'s output as something a release genuinely includes — most likely a real OTP application the release recognises, rather than a runtime path hack. The gate is behavioural, not structural: the built release must boot, serve the JSON:API, and successfully call through `timeline_facade` into Gleam code, proving the `.beam` files are actually in the release rather than smuggled in by `mix.exs` evaluation.

### Task graph: depend on output-declaring tasks, not `project://` inputs

Decided mid-build, after `project://` inputs caused three separate defects. It replaces the convention ADR-0002 documents; a superseding ADR records the change.

**The problem.** `project://<id>` folds another project's files into a task's hash. It is coarse (it walks whole directories, build trees included), it races (one task hashes a tree another is rewriting), and — the real defect — **it is not transitive**. `project://timeline_facade` hashes the facade's own files only; it does not reach the Gleam source behind it. Nothing tells you when a transitive edge is missing: you get a silent stale pass. That shape has bitten twice, on the Rust edge (Stage 4) and the Gleam edge (Stage 8).

**The mechanism.** Moon ignores a `deps:` entry for hashing *when the upstream task declares no `outputs`*. The converse is the fix: when an upstream task **does** declare outputs, the dependency contributes to the dependent's hash, and it composes — a change to C changes B's hash, which changes A's hash, transitively.

Note what is actually propagated. Moon folds the upstream task's **hash**, which is derived from that task's declared *inputs* — not a digest of its output bytes. So this is not Bazel-style artefact comparison: a comment-only edit upstream still re-runs everything downstream, because the upstream hash moved even though the compiled artefact is byte-identical. Precision comes from declaring narrow inputs, not from the artefact. The declared output's role is to make the dependency count for hashing at all.

**The rule.** Every task another task depends on declares real `outputs`. Downstream tasks express the edge as a task `deps:` entry on an output-declaring task, not as a `project://` input. A task with nothing meaningful to emit (a test task, say) is not a valid dependency target — give the project a `build`/`compile`/`package` task that produces the artifact, and depend on that.

Deliberately **not** solved with a checker. A tool asserting that every transitive edge is declared would keep the fragile convention in place and paper over it; the point is that the graph should make the missing edge impossible, not detectable.

Note this also bounds what Stage 11's plugin is for. Inferring `dependsOn` from `mix.exs` path deps automates ordering, which was never the correctness problem — and it cannot see the Cargo path dep behind `pricing_native` or the build-output path deps behind `timeline_facade` at all.

### Stage 9: e2e runs against the dockerized release, not a dev server

The e2e suite targets a **containerised stack running the `MIX_ENV=prod` release** from Stage 6c — server image plus Postgres, composed, configured by environment variables — never `mix phx.server` in dev mode against a developer's local database.

Rationale: a dev-server e2e proves the app works in a configuration nobody deploys. Running against the real release artifact exercises what actually ships — prod config and its runtime env-var reading, the release's own boot sequence and supervision tree, compile-time-vs-runtime config separation, and asset/static-file serving as built rather than as dev-reloaded. It also converts Stage 6c's Gleam-in-release concern from a one-time check into a standing one: if a future change stops the release bundling `timeline`'s BEAM files, an e2e test touching a timeline-backed endpoint fails, rather than the problem surfacing on someone's first real deploy.

Consequence for the Moon graph: `e2e:test` depends on the release image build (and `web`'s build), not on source. Playwright talks to the composed stack over HTTP at a configured base URL, so pointing the same suite at a deployed environment is a matter of configuration rather than a rewrite — provided the harness genuinely skips composing a local stack when given an external URL, which is a property to verify rather than assume.

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

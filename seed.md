# Consolidation Demo — Technical Specification

Reference project demonstrating Alembic's microservice consolidation playbook: a mixed-language modular monolith orchestrated by Moon, with enforced boundaries, change-aware test selection, and self-regenerating architecture documentation.

Written as a decision record. Each section states the decision, the rationale, and known consequences, so an agent or engineer can implement without re-litigating.

---

## 1. Build orchestration: Moon (v2+)

**Decision.** One Moon workspace orchestrating all components. Each component keeps its native toolchain (Mix, Cargo, pnpm); Moon owns the project graph, task graph, caching, and affected-detection. Not Bazel.

**Rationale.**
- Per-stack developer and IDE experience stays intact — ElixirLS, rust-analyzer, and the TypeScript server all see normal native projects, because Moon doesn't own compilation.
- Moon is polyglot by design: projects are declared in `moon.yml`, not inferred from `package.json`, so Elixir apps are first-class projects (Turborepo's JS-first model would require package.json wrappers).
- Moon v2's WASM plugin toolchains are the extension point for Elixir support (§2).
- Small community is acceptable — cutting-edge tooling is part of the consulting positioning.

**Mechanics to rely on.**
- Local: task-level caching keyed by a hash of declared inputs (file globs, command, env vars, toolchain versions). Cache hit replays outputs.
- CI: `moon ci` diffs against the base branch, maps changed files to owning projects, walks the graph to include dependents, runs only affected tasks.
- Tasks and builds are the same primitive: `test` tasks declared per project; `moon run :test` fans out; cross-project task deps let the e2e suite require server + PWA builds first.

**Consequences.**
- Correctness of caching and affected-detection rests entirely on declared inputs. Default globs are broad (safe, over-invalidates); tightening them risks missing real dependencies. Bias broad until hit rates hurt.
- Selection granularity is project-level: a one-line change reruns that project's whole suite. This deliberately pushes toward fine-grained components (§3).
- Moon only sees declared build dependencies — runtime relationships must be converted to build-time edges (§6) or they're invisible.

## 2. Elixir toolchain plugin for Moon

**Decision.** Write a WASM toolchain plugin that parses `mix.exs` path dependencies and infers `dependsOn` between Elixir projects, so the Mix dependency graph is not duplicated by hand in YAML.

**Rationale.** Elixir is tier 0 in Moon today (system tasks only, no manifest parsing). A dozen OTP apps with path deps means a dozen hand-maintained `dependsOn` lists that will drift. The plugin is contained, well-defined, and community-visible in both the Moon and Elixir ecosystems.

**Fallback.** Until the plugin exists, declare `dependsOn` manually and add a CI check that diffs declared deps against `mix.exs` path deps (a small script), so drift fails the build rather than corrupting affected-detection.

## 3. Component structure

### Elixir: poncho projects, not umbrella

- Each component is a standalone Mix project in its own directory, using path dependencies (`{:billing, path: "../billing"}`).
- Poncho over umbrella because: no shared config leakage, dependency direction is explicit, and path deps fail on cycles — closest available property to a compiler-enforced acyclic graph.
- Each app owns its own `test/` directory, so component-level test selection falls out of the structure.

### Within-app boundaries: `boundary`

- Add Sasa Jurić's `boundary` library from day one in every app — low ceremony, and makes any later split cheaper because internal boundaries already exist.
- Known limitation, accepted: boundary hooks the compiler tracer, and ExUnit test files are scripts evaluated at runtime — they never pass through the tracer, so boundary cannot see or govern the test tree. Test selection is path-convention-based instead (§7).

### Rust: NIF behind a facade app

- Performance-critical code lives in its own crate, its own Moon project.
- A dedicated Elixir facade app (e.g. `pricing_native`) holds the Rustler NIF and nothing else. All upstream code depends only on the facade's public functions.
- `boundary` enforces that no other app references the NIF module directly — this is the one place the opaque-wrapper problem is checkable.
- The crate compiles outside Mix's dependency graph, so declare the crate → facade edge explicitly in Moon (`dependsOn`). This is what makes a Rust change invalidate Elixir tests; native test-impact tooling cannot see across this boundary.
- Do not use precompiled NIF binaries in the demo — a binary artefact has no source dependency edge at all, which defeats the demonstration.

### TypeScript: PWA in a pnpm workspace

- pnpm workspace + TypeScript project references for package boundaries and incremental compilation.
- Module-boundary enforcement is lint-level in this ecosystem (advisory unless CI blocks it) — CI blocks it.

### Optional extension: mobile

- Android (Gradle) and iOS (xcodebuild/Fastlane) run as tier-0 system tasks: Moon decides *whether* to invoke the build (affected-detection, ordering); Gradle's own cache handles intra-build speed. Not in demo scope unless a client conversation needs it.

## 4. Domain model: declarative Ash resources

**Decision.** The Elixir domain layer is Ash. Resources are the single declarative description from which the data layer, actions, and API are deterministically generated.

**Rationale.** This is the narrow slice of model-driven engineering that actually works: the generated part is genuinely mechanical (schema-shaped), so model and code cannot diverge. Full-behaviour code generation from models is explicitly out of scope — that approach's historical failure mode (model captures structure, not behaviour; hand-edits cause permanent divergence) is the thing to avoid.

**Consequence.** The OpenAPI spec (§6) is generated from the Ash API definition, not hand-written — one source of truth from resource to published contract.

## 5. Data layer: one Postgres, schema per component

- Single PostgreSQL database. Each component owns a Postgres schema (isolated namespace): one connection story, one backup, one migration path; cross-schema queries possible when genuinely needed, not routine.
- **Enforcement is role-based**: a database role per component with grants limited to its own schema, so a cross-boundary query is a hard error, not a convention.
- **Separate connection pools per component** (an Ecto Repo per schema, each connecting as its component's role), rather than `SET ROLE` on checkout. Rationale: `SET ROLE` works but demands reset discipline (a missed `RESET ROLE` leaks permissions to the next checkout), costs a round trip per checkout, and breaks prepared-statement caching across roles. Structural isolation over discipline. Size each pool small.
- Migrations are per-component tasks in Moon, so schema changes participate in affected-detection.
- Schema *merging* (entity reconciliation across components) is deliberately out of scope for the structure — in a real engagement it is deferred, isolated per bounded context, and priced separately, because reconciling divergent entity models is data cleaning requiring domain knowledge, with no rollback story once both sides have written.

## 6. Runtime edges become build-time edges

- The Elixir server publishes an OpenAPI spec, generated from Ash.
- The PWA depends on a client package *generated from that spec at build time*. The consumer's build declares a dependency on the producer's spec.
- Effects: the edge appears in Moon's graph (affected-detection covers it); a breaking API change fails the consumer's build instead of surfacing at runtime; contract testing falls out as a side effect (the generated client won't compile against an incompatible spec).
- Caveat: openapi-generator output quality varies sharply by target language and Elixir is among the weaker targets. For the TS client the standard generators are adequate; if an Elixir-side consumer is added, generate a thin client in-house rather than fighting the generator.

## 7. Testing strategy

**Governing principle.** A component's test suite must be a real proof: runnable alone, without stubbing out the rest of the system. Assessment metric worth demonstrating: for a change inside a component, what fraction of confidence comes from that component's own tests versus top-level integration tests? If mostly the latter, the boundaries are decorative.

**Layers.**

1. **Component suites** — each Elixir app's ExUnit suite, each crate's `cargo test`, each TS package's runner. Run via Moon `test` tasks; selected by affected-detection.
2. **Test selection** — build-graph-based (sound but coarse), via Moon. Coverage-map-based per-test selection is explicitly rejected: unsound in principle (blind to new code paths, config, dependency versions, generated code) and fragile in practice.
3. **Within-app selection (Elixir)** — mirror boundary structure in the test tree so `lib/billing` maps to `test/billing`, and derive selection from paths (Mix alias driven by git diff). Convention-checkable; no tag bookkeeping.
4. **End-to-end suite** — a Moon task depending on the server and PWA build tasks. Runs full on main and nightly as the backstop; selection is a fast pre-merge gate, never the final word. No deploy without the full e2e suite green.
5. **Executable acceptance specs** — Gherkin feature files living in the repo, wired to ExUnit (the Elixir tooling here is thinner than Ruby's Cucumber; treat the wiring library as a swappable detail, the principle — specs that fail when behaviour changes — is the requirement).
6. **Visual regression (optional)** — Playwright snapshots against committed UI mocks. Include as a demonstration, flag the known brittleness; it's the only mechanical check the mock artefact gets.

**Hermeticity posture.** Full Bazel-style sandboxing is not the goal. Approximation: proto-pinned toolchain versions feed task hashes; CI builds run in a container with nothing preinstalled, so under-declared inputs surface as immediate failures rather than stale cache hits. Locally, fast unsandboxed iteration; containerised build available as a pre-push option.

## 8. Specification-per-component ("the spec directory")

**Problem being solved:** specification decay — acceptance criteria, behaviour, and UI intent live in a ticket, get implemented once, and die when the ticket closes.

**Decision.** Each component carries a `spec/` directory holding:

- `features/` — Gherkin acceptance criteria (executable, per §7.5)
- `mocks/` — dated UI mock snapshots
- `decisions/` — ADRs: dated, immutable markdown capturing *why*, not *what*

Everything an agent needs sits in one context window; same for a new engineer.

**UI mocks — lifecycle.** Mocks are deliberately cheap: iterated in lightweight tooling (Figma / Storybook-assembled from real components) with PMs and designers, *outside* the repo. When a piece is built, a snapshot is committed to `spec/mocks/` as a dated artefact — honest about being the intent at build time, not a maintained truth. The mock is never the source of truth; the durable asset is the component library it's assembled from. The moment a mock becomes authoritative it stops being cheap, which destroys its value.

**Agent workflow this enables:** implementation context = Gherkin criteria + mock snapshot + Ash resource declarations. Structure (Ash), behaviour (features), user experience (mocks) — with ADRs for the reasoning.

## 9. Architecture explorer

**Decision.** A self-built interactive explorer, regenerated in CI on every build. No Backstage (operating cost, not licence), no commercial tooling.

**Inputs.**
- `moon project-graph` JSON — the real cross-language dependency graph
- git history — change frequency per project
- `capabilities.yml` — hand-maintained capability → component mapping; the only manual input, kept honest by being small (a dozen capabilities, not hundreds)

**Rendering.** Static site; Cytoscape.js or D3 for the interactive graph. Regenerated from the same inputs as the build, so it cannot drift.

**Audience split.**
- Zoomed out (CTO/architect): capability map + change-frequency and coupling overlays — the "where to invest next" view. Not generated *from code structure* alone; capability framing is what makes it stable across refactors.
- Zoomed in (engineer/agent): the project graph itself, per-component detail linking to the spec directory.

**Known gap, turned into the pitch:** the graph only shows declared build edges. In the demo's "before" state, runtime HTTP edges are invisible — exactly the client's situation. §6 makes them visible; consolidation makes them in-process. Distribution is what made the architecture invisible.

## 10. Demo narrative: three states in one repo

The repo should demonstrate the playbook's sequence, not just its end state. Suggested mechanism: tagged stages (or long-lived branches):

- **State A — estate**: components as separately-deployed services in one workspace; runtime HTTP calls between them; explorer shows a sparse, dishonest graph.
- **State B — one workspace, real edges**: generated clients convert runtime edges to build edges; separate deploys retained; explorer now shows the true topology; `moon ci` demonstrably runs only affected work.
- **State C — modular monolith**: core absorbed first, keeping its HTTP interface as a facade (external callers unchanged); each subsequent absorption converts a network call to a function call; one release; Postgres schemas with role enforcement.

The consolidation direction is core-outward: the core keeps its API as a facade, so every step after the first is a genuine consolidation (each absorbed service internalises its edge to the core). The honest risk to showcase, not hide: the network→function-call seam, where callers that tolerated timeouts and eventual consistency now see synchronous calls and exceptions. Make one such seam explicit in the demo with a test that catches the behavioural difference.

## 11. Component inventory (proposed minimum)

| Project | Language | Notes |
|---|---|---|
| `core` | Elixir/Ash | Domain model, publishes OpenAPI; HTTP facade in State C |
| `billing` | Elixir/Ash | Own Postgres schema/role; absorbed in State C |
| `identity` | Elixir/Ash | Own schema/role |
| `pricing` | Rust crate | Performance-critical; `cargo test` suite |
| `pricing_native` | Elixir | Rustler NIF facade; only app allowed to reference the NIF module |
| `web` | TypeScript | PWA; depends on generated `core-api-client` |
| `core-api-client` | TypeScript (generated) | From core's OpenAPI spec; build-time edge |
| `e2e` | Playwright | Depends on `core` + `web` builds |
| `explorer` | TypeScript | Static-site generator consuming project-graph JSON + git stats + `capabilities.yml` |
| `moon-elixir-plugin` | Rust→WASM | Mix path-dep inference (§2); may live in its own repo |

Gleam is a natural swap-in for one Elixir component if community visibility for the demo matters; nothing above depends on which BEAM language a component uses.

---

*Alembic — consolidation demo spec. Derived decisions; supersede via ADR, not by editing history.*

# ADR-0001: Gleam ↔ Elixir build integration on the BEAM

**Status:** Accepted (Stage 5)
**Context:** PLAN.md's own "Open risks" table flags this as unsettled:
"Gleam compiles to Erlang `.beam` output consumed by the facade app; the
edge is a declared Moon `dependsOn`. Settle the exact mechanism in stage 5
and record it as an ADR."

A proper `spec/decisions/` ADR directory convention lands in Stage 8; this
file is deliberately just a markdown file in the meantime, for Stage 8 (or
anyone else) to relocate.

## Decision

`timeline` is a standalone Gleam project (its own `gleam.toml`, built with
plain `gleam build` / `gleam test`, no Mix involvement at all). It compiles
to ordinary `.beam` files under `timeline/build/dev/erlang/<package>/ebin/`
— one such directory per Gleam package it depends on (itself, `pog`,
`gleam_stdlib`, `gleam_erlang`, `gleam_otp`, `gleam_time`, and `pog`'s own
Erlang-native transitive deps `pgo`, `pg_types`, `backoff`, `exception`,
`opentelemetry_api`).

`timeline_facade` is a separate, ordinary Mix project. Its `mix.exs` walks
`../timeline/build/dev/erlang/*/ebin` and calls `Code.prepend_path/1` on
each one, every time `mix.exs` is evaluated (i.e. on every `mix` command:
`compile`, `test`, `run`, ...). That is the *entire* interop mechanism —
nothing is recompiled, re-fetched, or re-linked; it only makes `timeline`'s
already-built `.beam` files loadable by the BEAM `timeline_facade` runs on.
`TimelineFacade.Gleam` then calls straight into the compiled Gleam module
(`:timeline.append_shift_started/2`, etc.) as plain Erlang function calls —
Gleam functions and modules are just Erlang functions and modules once
compiled; there is no special runtime bridge, marshalling layer, or NIF
involved.

Two supporting details, both non-obvious and both confirmed necessary by
hitting the failure they prevent:

- **`prune_code_paths: false`** in `timeline_facade`'s `mix.exs` project
  config. Since Elixir 1.15, Mix prunes the code path after compilation
  down to only the current app + its declared Mix deps. `timeline` is not
  a Mix dep (see "Alternatives considered" below), so without this flag
  its `ebin` dirs get silently pruned right after boot and every
  `:timeline.*` call becomes `UndefinedFunctionError`. (This is the same
  flag `mix_gleam`'s own README documents needing, for a different reason
  — see below.)
- **`Application.ensure_all_started(:pgo)`**, called from
  `timeline/src/timeline/db.gleam` before every connection attempt. `:pgo`
  (the Erlang Postgres driver `pog` wraps) lazily creates a query-plan
  cache ETS table in its own OTP `application` start callback. Nothing
  triggers that callback when `timeline` is consumed as plain code-path
  modules rather than a real dependency in an application's supervision
  tree, so the very first query failed with `the table identifier does
  not refer to an existing ETS table` until this call was added.
  `gleam test`/`gleam run` don't need it, because Gleam's own runner
  already starts every application on the code path before calling
  `main/0` — this only bites when Gleam code is loaded into somebody
  else's BEAM instance instead.

## Alternatives considered

### `mix_gleam` (gleam-lang/mix_gleam)

This is the community/Gleam-team Mix-compiler-plugin approach: it adds a
`:gleam` Mix compiler that runs `gleam compile-package` as part of a
*single* Mix project's own `mix compile`, treating `.gleam` source files
under that project's own `src/` as first-class input alongside its `.ex`
files.

Ruled out for two reasons:

1. **Wrong shape for this repo's structure.** `mix_gleam`'s whole model is
   Gleam source living *inside* the same Mix project that consumes it (one
   project, two source languages). PLAN.md's structure requires `timeline`
   and `timeline_facade` to be genuinely separate Moon projects — `timeline`
   needs its own `gleam.toml` and a standalone `gleam test` task
   (`timeline:test`) that proves the Gleam logic on its own, independent of
   Elixir entirely. Folding the Gleam source into `timeline_facade` would
   collapse that separation and the two-project gate PLAN.md's stage table
   asks for (`moon run timeline:test timeline_facade:test`, both projects).
2. **Staleness.** The latest Hex release, `0.6.2`, shipped November 2023 —
   about three years old as of this stage. It wasn't ruled out purely on
   that basis (it may well still work for its intended use case), but
   combined with (1) there was no reason to take on it.

### Plain Mix `path:` dependency

The simplest-sounding option — `{:timeline, path: "../timeline"}` in
`timeline_facade`'s `mix.exs` — was tried directly and fails immediately:

```
Could not compile :timeline, no "mix.exs", "rebar.config" or "Makefile"
(pass :compile as an option to customize compilation, set it to "false" to
do nothing)
...
could not find an app file at "_build/dev/lib/timeline/ebin/timeline.app".
```

Mix requires exactly one of those three manifest files at a path
dependency's target. A bare `gleam.toml` project satisfies none of them, so
this option doesn't exist without also adopting something like `mix_gleam`
(which teaches Mix how to treat a Gleam package as a dependency) — which
brings back reason (1) above.

## Rough edges / known limitations

**`boundary` cannot enforce "sole caller of `:timeline`."** PLAN.md
describes `timeline_facade` as "boundary-enforced," mirroring
`pricing_native`'s Rustler-NIF pattern (a `use Boundary, exports: []`
sub-module holding the raw calls, checked the same way Stage 2 checked
`core` and Stage 4 checked `pricing_native`: inject a forbidden direct
reference, confirm `mix compile --warnings-as-errors` fails, remove it,
confirm clean).

That check was run in this stage — a throwaway `TimelineFacade.Probe`
module calling `:timeline.current_availability/1` directly — and
**`mix compile --warnings-as-errors` passed clean**, i.e. `boundary` did
not catch it. Traced to the root cause, not just observed:

- `boundary`'s cross-app classification (`Boundary.app/2` in
  `lib/boundary.ex`) is keyed off a `module -> app` map built once per
  compilation (`lib/boundary/mix/view.ex`), populated from
  `Application.spec(app, :modules)` for every application Mix knows about.
- `lib/boundary/mix.ex` filters that module list down to only entries
  whose name starts with `"Elixir."` — i.e. `boundary` only ever considers
  genuine Elixir modules.
- Gleam compiles to plain, unprefixed Erlang atoms (`:timeline`,
  `:"timeline@event"`, ...). No amount of registering `:timeline` as a
  loaded OTP application changes that: this stage tried patching the
  loaded application's `:modules` list (Gleam's own generated `.app` file
  unconditionally ships `{modules, []}`, confirmed by reading
  `timeline/build/dev/erlang/timeline/ebin/timeline.app` directly, which
  independently breaks OTP's own module → application reverse lookup) —
  `Application.get_application(:timeline)` did start resolving correctly
  afterwards, and `boundary` *still* didn't flag the probe, because its
  filter rejects the module name itself, not just the app lookup.

  This is why `pricing_native`'s equivalent pattern *does* work: the
  Rustler NIF is wrapped in `PricingNative.Native`, a genuine
  `Elixir.PricingNative.Native` module compiled by Mix as part of that
  same app — `boundary` sees it like any other in-app module. Gleam's
  bare-atom modules have no equivalent wrapper unless one is hand-written
  (see "possible follow-up" below), so **this asymmetry would exist
  regardless of which interop mechanism were chosen** — it is not
  specific to the code-path-loading approach here; `mix_gleam`-compiled
  Gleam code would produce the exact same bare-atom modules.

  Compensating control actually in place: `timeline_facade:test`'s Moon
  task greps `lib/**/*.ex` for `:timeline.` outside
  `lib/timeline_facade/gleam.ex` and fails the build if it finds one. This
  is enforced (it runs on every `timeline_facade:test`, same as the real
  gate), but it is a textual convention check, not a structural one — it
  would not catch, for instance, `apply(:timeline, :current_availability,
  [id])`. A possible follow-up, not attempted here: hand-write a thin
  `Elixir.Timeline.*` wrapper module per Gleam function inside `timeline`'s
  own build output (or generate one), giving `boundary` a real,
  classifiable Elixir module to see — at the cost of maintaining that
  wrapper by hand alongside `timeline.gleam`'s own public API.

**`rebar3` must be on `PATH` to build `timeline` at all**, and proto does
not manage it. `pog` depends on `pgo` (the underlying Erlang Postgres
driver), which depends on `backoff`, a plain rebar3-built Erlang package —
`gleam build`/`gleam test` shell out to `rebar3` to build it. `timeline:test`'s
Moon task provisions it via Mix's own first-party `mix local.rebar
--if-missing --force` (the same mechanism every Mix project with
Erlang-native Hex deps relies on, fetching from Hex's own build CDN,
`https://builds.hex.pm`) rather than installing anything outside the
proto-managed toolchain, then adds its install directory to `PATH` for
that task only. This is a real environment gap worth flagging for anyone
extending the Gleam toolchain story (Stage 11's `moon-elixir-plugin` or a
future first-party Gleam Moon toolchain might want to own this instead).

**`timeline/build/dev/erlang/` also contains real, vendored copies of
Elixir's own bundled applications** (`mix`, `elixir`, `eex`, `logger`) —
because one of `timeline`'s dev-dependencies (`gleeunit`, transitively)
deals in Elixir-target packages, and Gleam's Hex client fetches those the
same way as any other dependency. `timeline_facade`'s `mix.exs` explicitly
skips `Code.prepend_path/1` for any directory whose name matches an
already-loaded application, specifically to avoid shadowing the live,
currently-running Mix/Elixir/EEx/Logger modules with a stale vendored copy
— confirmed necessary in this stage: an earlier, unconditional version of
this loop crashed `mix compile` by attempting to reload a vendored copy of
Mix's own `.app` file over the live one.

**No supervision tree.** `timeline`'s Postgres connection pool (`pog`,
via `timeline/src/timeline/db.gleam`) is started, at most once per role
per running VM (memoized in `:persistent_term` — see below), completely
outside any OTP supervision tree — `timeline_facade` has no application
callback module wiring it in. This is acceptable for this stage's test
suite and facade calls (short-lived, low-concurrency), but is a real gap
for anything long-running: if the pool crashes, nothing restarts it, and
nothing but the next failed query would tell you. A production wiring
would want the pool added to `timeline_facade`'s own supervision tree
instead, per `pog`'s own README recommendation.

**One pool per role, not one per call — and why.** An earlier version of
`timeline/src/timeline/db.gleam` started a brand new `pog` connection pool
on every single call into `timeline`, unsupervised, and never stopped the
old one. Besides being wasteful, this caused a real, reproduced bug under
`timeline_facade`'s ExUnit suite: a `rebuild_availability` call using a
freshly-started pool would sometimes read back zero events for a
technician whose events had just been written moments earlier over a
*different* freshly-started pool. Memoizing a single pool per role in
`:persistent_term` (started lazily, on first use) removed this. That
introduced a second, subtler bug on top: `pog.start` (built on
`gen_server`-style `start_link` semantics) links the new pool process to
whichever process calls it *permanently*, not just during startup — so
the first caller to hit an uncached role is very often a short-lived
ExUnit test process, and that process later exiting abnormally (e.g. an
unrelated failing `assert` in the same test run) propagated a kill signal
over the link and took the shared pool down with it, breaking every
*other* test relying on the cached connection. Fixed by calling
`:erlang.unlink/1` on the pool's pid immediately after a successful start,
in the same breath as the memoization above — severing the link is safe
here specifically because nothing is supervising the pool from the
Elixir/Mix side anyway (see the previous point).

**Connection details are hardcoded, not environment-configurable.**
`timeline/src/timeline/db.gleam` connects to a fixed
`localhost:5432/baalbek` (matching `.devcontainer/docker-compose.yml`),
unlike `core`'s `CORE_PG_*` / `BOOTSTRAP_PG_*` environment-variable
pattern. A deliberate simplification for this stage's scope, not an
oversight — adding env var overrides (via the `envoy` package, or a
hand-rolled `os:getenv` external) is a small, additive change if a future
stage needs it (e.g. a real CI environment with different connection
details, or multiple Postgres instances).

**`gleam_stdlib` is pinned below 1.0** in `timeline/gleam.toml`
(`0.63.2`), not the latest release. `gleam_stdlib >= 1.0.0` declares
`gleam = ">=1.14.0"` in its own `gleam.toml`, but this repo's root
`.prototools` pins `"asdf:gleam" = "1.13"` — confirmed by hitting `error:
Incompatible Gleam version ... requires >=1.14.0` against the latest
release before pinning down to `0.63.2`, the newest version that doesn't
carry that requirement. Whoever bumps the Gleam proto pin past 1.14 should
also lift this ceiling.

## What was verified, concretely

- `gleam build` / `gleam test` inside `timeline/` compile and pass
  standalone, including a live-Postgres round trip (append events via
  `pog`, rebuild an availability projection from the log, query the
  materialised projection) — not just the pure fold logic.
- `mix test` inside `timeline_facade/` passes standalone, calling
  `TimelineFacade`'s public functions, which call straight through to the
  compiled Gleam code — no stubbing.
- `moon run timeline:test timeline_facade:test` passes end to end.
- `moon run timeline_facade:test` after `moon clean --all` (which deletes
  `timeline/build`) only succeeds because the declared `dependsOn` forces
  `timeline` to build first — deleting `timeline`'s build output and
  running `mix test` directly inside `timeline_facade/` (bypassing Moon)
  reliably reproduces `UndefinedFunctionError` on the very first
  `:timeline.*` call, proving the dependency is real, not decorative.
- The `boundary`-violation probe described above: confirmed it does *not*
  get caught by `boundary`/`mix compile --warnings-as-errors`, traced to
  root cause, and covered instead by a compensating grep-based check in
  `timeline_facade/moon.yml`'s `test` task.

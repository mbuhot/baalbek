# ADR-0010: Third-party dependencies compile in their own task

**Status:** Accepted. Amends adr-0006.
**Date:** 2026-09-07
**Stage:** mid-build, after Stage 12's first full-graph CI run

## Context

A full-graph CI run took 36m37s, and most of it was one dependency tree
compiled over and over. From that run's log:

```
core:build     | Compiling lib/ash/error/query/not_found.ex (it's taking more than 10s)
identity:build | Compiling lib/ash/error/query/not_found.ex …
billing:test   | Compiling lib/ash/error/query/not_found.ex …
billing:build  | …
identity:test  | …
```

The poncho layout is what makes each app compile its own copy — seed.md §3
chose it over an umbrella deliberately, and each app owns its own `_build`.
That is per *app*. The repetition above is per *task and environment*: three
Ash apps compiled Ash three times each, because `build` compiled it at
`MIX_ENV=dev` and `test` compiled it twice more — once at the default `dev`
for `mix <app>.bootstrap`, then again at `test` for the suite.

None of that has to happen when only first-party code changes. `mix.exs` and
`mix.lock` decide the third-party tree; nothing under `lib/` does.

## Decision

### One `deps` task per Elixir project, keyed on the manifest alone

Each Elixir project gets a `deps` task whose `inputs` are `mix.exs` and
`mix.lock` and nothing else, and whose `outputs` are the fetched sources and
the compiled third-party tree. `build` and `test` take a task `deps:` edge on
it, which is adr-0006's convention: the edge contributes to their hash because
the upstream task declares outputs.

Measured on `core`, in a clean git worktree on the container's own filesystem,
on 24 cores. Every row compares one shape with itself, before the split and
after it; a cold *before* against a warm *after* would measure the cache and
not the change:

| shape | before | after |
|---|---|---|
| warm: `core:build`, build tree and task cache both warm | 2.66s | 2.66s |
| cold: `core:build`, no build tree, no `deps/`, no task cache | 55.6s | 132.6s |
| cold: `core:build core:test` in one run | 111.9s | 141.1s |
| fresh checkout, restored task cache, one edit under `core/lib` | 54.1s | 2.9s |

Only the last row improves, and it is the shape CI runs:
`.github/workflows/ci.yml` restores `.moon/cache` on a pull request, and a
first-party edit changes neither `mix.exs` nor `mix.lock`, so `core:deps` hits
— half a second to restore 25 dependency source trees and 25 compiled ones,
where the shape before had to compile them. 18.7×.

The two cold rows are worse, 2.4× on the single task. `deps` compiles the tree
at `dev` and then at `test` in sequence, and both `build` and `test` wait on
it, where before each compiled only the environment it needed and the two ran
in parallel. Nothing about the split helps a run with no cache to hit.

`core:deps` itself costs 1m59s cold — two environments, 25 packages — and 4.5s
when a `mix.lock` change re-runs it against a warm tree.

### The task compiles named dependencies, never a bare `mix deps.compile`

`server` has sixteen Mix path dependencies once the closure is counted, and
`timeline_facade` eleven. A bare `mix deps.compile` compiles those too, which
would key a sibling's compiled code on this project's manifest — the coupling
this split exists to remove.

So the task names its dependencies, and the names come from
moon-elixir-plugin, which already evaluates every `mix.exs` through
`Mix.Project.in_project/3`. It now also reads `mix.lock` and hands the list to
a `deps-list` task as `$MIX_THIRD_PARTY_DEPS`;
`../../moon-elixir-plugin/spec/decisions/adr-0003-the-plugin-hands-over-the-third-party-dependency-list.md`
records why the lock is the right source and why the list travels on a task of
its own. Verified: `server:deps`' cache archive holds 3,097 files under
`build/dev/lib` and **no** `core`, `identity`, `billing`, `pricing_native`,
`timeline_facade` or Gleam directory.

An empty list means the plugin could not read the manifest. The task then
fetches sources and compiles nothing, leaving `build` and `test` to compile
the tree themselves, which is exactly the behaviour this ADR replaces. It is
the one case where over-compiling would be unsafe, so the task does not do it.

### Two build trees, `build/dev` and `build/test`

adr-0006 put each app's Moon-visible artefact in `<project>/build/` and argued
the path should name no environment, because one task owned one tree. Two
tasks now own two trees, so the path names the environment again:
`build/dev/lib/<app>/ebin` replaces `build/lib/<app>/ebin`.

Mix does not notice. `MIX_ENV=test mix compile` against a tree compiled at
`dev` recompiles nothing at all — measured, 0.5s, no output — so the
separation has to come from the path. The whole `test` task therefore runs at
`MIX_ENV=test`, and each app's `mix <app>.bootstrap` moved out of the test
command into a `bootstrap` task at the same environment. That is where the
third Ash compile went.

### `deps` owns `deps/`, and it is the only task that fetches

Mix's compile manifests record each source file's timestamp, so a
`mix deps.get` that re-fetches the sources invalidates the artefacts that were
built from them. Measured: with a warm build tree and freshly fetched
sources, `mix compile` recompiled the entire dependency tree, 48s. A cache hit
that restored only the artefacts would therefore have saved nothing: CI
restores `.moon/cache` on a pull request but the checkout is always fresh, so
`deps/` is never already there. So `deps/**/*` is a declared output, and
moon preserves mtimes on restore (measured on a file stamped 2020-01-01).

One dependency cannot be carried that way. moon's output globs match dotfiles
— `.hex`, `.formatter.exs`, `.github` are all archived — but skip a nested
`.git`, so `ash_boundary`, a git dependency, comes back unfetched:

```
core:build | Unchecked dependencies for environment dev:
core:build | * ash_boundary (https://github.com/mbuhot/ash_boundary.git - 8e358e3f…)
core:build |   the dependency is not available, run "mix deps.get"
core:build | ** (Mix) Can't continue due to errors on dependencies
```

The first fix was to leave `mix deps.get` in every compiling task, which put a
fetch in 24 tasks per full `moon ci` run where 6 needed one. What Mix is
re-checking there is an invariant moon already owns: `deps` is keyed on
`mix.exs` and `mix.lock` and restores `deps/` as a declared output.

So every other task passes `--no-deps-check`, and **that alone is wrong**,
because the same check also performs the step that compiles a `path:`
dependency into the build path. Measured in the state the archive actually
restores — `timeline_facade/build/test/lib` holding `boundary` and the app's
own directory, nothing else:

```
$ mix test --no-deps-check
** (Mix) Could not start application timeline: could not find application file: timeline.app
$ mix test
Result: 4 passed
```

`server` cannot take either branch: with its five path deps absent from the
tree and `deps/ash_boundary/.git` hidden, `--no-deps-check` gives
`could not find application file: core.app` and the plain command gives
`the dependency is not available, run "mix deps.get"`.

The path dependencies are therefore compiled **by name**, from a second list
the plugin reads out of the same manifest
(`../../moon-elixir-plugin/spec/decisions/adr-0003-the-plugin-hands-over-the-third-party-dependency-list.md`):

```
{ test -z "$MIX_PATH_DEPS" || mix deps.compile $MIX_PATH_DEPS; } && mix test --no-deps-check
```

The guard matters: a bare `mix deps.compile` with an empty variable compiles
every dependency, which is the coupling this ADR exists to remove.
`--no-deps-check` is written into every compiling task and no project replaces
it. The section below on `$MIX_PATH_DEPS` records why the one escape that
existed is gone.

A bootstrap task cannot use the flag — `mix ecto.create --no-deps-check` and
`mix ecto.migrate --no-deps-check` still fail on the unverifiable git dep, and
`mix <app>.bootstrap` takes no flags — so those run
`mix do loadpaths --no-deps-check + …`, where one `loadpaths` covers every
task after it and one BEAM start serves all four.

### `$MIX_PATH_DEPS` is the closure, and its manifest answers once

`mix deps.compile` links exactly the applications it is named, and it does not
descend. The first version of this list carried each project's **direct** path
deps, so `server` was handed
`billing core identity pricing_native timeline_facade` and the eleven Gleam
applications behind that facade were never named. `server` then compiled
against modules it had not loaded, and exited 0 doing it:

```
server:build | warning: cannot infer signatures from :gleam_stdlib because it is not loaded
server:build | Generated server app
▮▮▮▮ server:build (5s 169ms, f92a23e8)
```

moon cached that ebin. `server:openapi` boots the application, and that is
where a warning became a failure — run 34138959290 on `main`:

```
server:openapi | ** (Mix) Could not start application gleam_stdlib: could not find application file: gleam_stdlib.app
```

So the plugin walks each manifest's path deps recursively and hands over the
closure. `server` is now given sixteen names. `mix deps.compile` keeps its own
topological order and ignores the order of its arguments, so `timeline` is
linked before `timeline_facade` compiles.

Measured in the state moon's archive actually restores, with
`server/deps/ash_boundary/.git` moved aside and the eleven Gleam directories
deleted from `server/build/dev/lib`: `mix deps.compile` over the sixteen names
exits 0, links all eleven, and `mix compile --no-deps-check` then emits no
`is not loaded` warning. The same command over the six names a cold graph gave
before the manifest was fixed also exits 0, links only `timeline`, and leaves
ten `is not loaded` warnings behind.

That alone is not enough, and the reason is the second half of this decision.
The plugin evaluates a manifest **while moon builds the project graph**, before
any task has run. `timeline_facade/mix.exs` computed its path deps with a
`File.ls` over `../timeline/build/otp`, which `timeline:build` writes, so on a
cold graph it answered with a one-application fallback and on a warm graph with
all eleven. A closure over a list that is itself wrong is still wrong: with the
walk in place and the manifest unchanged, `server`'s cold list was
`billing core identity pricing_native timeline timeline_facade` and ten
applications were still missing.

`timeline_facade/mix.exs` therefore writes the eleven names out and checks them
against the directory whenever the directory exists. One answer, cold or warm.
That is the general rule for this workspace: **a manifest the plugin reads must
not depend on state a task produces.** `moon-elixir-plugin`'s README records the
same constraint from the plugin's side.

The drift check is what makes the written-out list safe to trust. Measured with
one extra directory under `timeline/build/otp`: `mix deps.get` in
`timeline_facade` fails with the two lists side by side, and moon logs the same
message twice — once for `timeline_facade` and once for `server`, reached
through the closure. A project whose closure cannot be evaluated gets no list,
which is the loud failure rather than the short one.

Measured on a cold project graph, with every Elixir `build/` tree,
`timeline/build` and `.moon/cache` removed:

| `$MIX_PATH_DEPS` | before | after |
|---|---|---|
| `server` | `billing core identity pricing_native timeline_facade` | `backoff billing core exception gleam_erlang gleam_otp gleam_stdlib gleam_time identity opentelemetry_api pg_types pgo pog pricing_native timeline timeline_facade` |
| `timeline_facade` | `timeline` | the eleven |

### The gate is cold-graph, because a warm one cannot see this

Every gate this decision was measured against before it reached `main` ran on
a warm build tree and a warm project graph — including the 28-task run recorded
above. On a warm graph the manifest already saw all eleven applications, and an
earlier run had already linked them into `server`'s tree, so a list that could
not have produced them passed. The measurement that would have disproved the
design was the one nobody ran.

A gate for this class of defect has to remove, in one sequence:

- every Elixir project's `build/` tree,
- `timeline/build`,
- moon's project-graph cache (the `states` directory under `.moon/cache`),

and only then run the tasks. Exit 0 is not enough on its own: `server:build`
exited 0 throughout the failure above. The gate also asserts that
`timeline_facade:build` and `server:test` emit no
`cannot infer signatures` or `is not loaded` warning, and that `:timeline` and
`gleam_stdlib` are present in both projects' build trees.

Measured, from that state, with `.moon/cache` removed entirely so nothing was
restored: `server:test server:openapi server:release timeline_facade:test
timeline_facade:build core:test billing:test identity:test e2e:test
moon-elixir-plugin:test root:test` — 37 tasks, exit 0, 4m38s;
13/18/21/27/4 ExUnit tests and 6 Playwright tests passed; zero
`cannot infer signatures` or `is not loaded` lines in the whole log; and
`timeline` and `gleam_stdlib` present in all four of `server`'s and
`timeline_facade`'s `build/dev/lib` and `build/test/lib`.

The same run also settles the hash: `timeline_facade:build` hashes `1b304239`
on a cold graph over a cold tree, and `1b304239` again on a cold graph over the
warm tree it produced. `server:test` is `275bfe22` both times. Before the
manifest wrote its list out, those two states gave different hashes, which is
the "extra run" the consequence below used to record.

`server:release` is the one exception and still runs `mix deps.get --only
prod`: its prod tree is nobody else's, and there is no prod dependency list to
compile because the plugin reads the manifest at one `MIX_ENV`. So the count
per full CI run is 24 tasks fetching before, 7 after — the six `deps` tasks
and the release. Confirmed in the cold gate below: `Resolving Hex
dependencies` appears once each in `billing:deps`, `core:deps`,
`identity:deps`, `pricing_native:deps`, `server:deps`,
`timeline_facade:deps` and `server:release`, and in no `build`, `test`,
`bootstrap` or `openapi` task. `server:image` fetches inside its own
container, where there is no moon cache to restore.

### The three task shapes live in `.moon/tasks/elixir.yml`

`deps`, `build` and `test` are identical across the six Elixir projects apart
from names, so they are declared once, inherited by
`inheritedBy: {language: elixir}`. `$project` in an input, output or argument
expands to the project id, which is what lets one declaration name
`build/dev/lib/$project/ebin`; every OTP application in this workspace is
named for its directory, as adr-0001 of the plugin records.

`inheritedBy` is not optional. moon 2.5.4 does **not** scope
`.moon/tasks/<language>.yml` by its filename: without the condition, the
Elixir tasks were inherited by every project in the workspace, `web` and
`explorer` included, which put `mix.exs` and `mix.lock` in a TypeScript task's
inputs and gave `timeline` and `root` a phantom `build` task.

A project declares only what differs: its `bootstrap` task, the sources it
actually has (`priv/**/*`, `native/**/*`), and `server`'s `openapi`, `release`
and `image`. `CARGO_TARGET_DIR` is project-level `env` in the two projects
that involve a crate, one entry each, and it names one shared directory:
cargo namespaces by package inside it, so the per-crate suffix the six copies
carried was a name that would be false as soon as a second NIF existed.

### `^:build` replaces the hand-written dependency blocks

`server/moon.yml` repeated the same five-item block — `core:build`,
`identity:build`, `billing:build`, `pricing_native:build`,
`timeline_facade:build` — in four tasks. moon's `^:build` scope expands to the
`build` task of every project this one depends on, and for an Elixir project
that list is *inferred* from `mix.exs`. So the inferred `dependsOn` now
carries the hash edges, which is what adr-0001 of the plugin said it did not:

> `dependsOn` orders and scopes; it does not invalidate.

That was true only because the task deps were written out by hand.

Three measurements settle the substitution.

**The expansion is exactly the five projects.** `moon task server:release
--json` and `server:image --json` list `core:build`, `identity:build`,
`billing:build`, `pricing_native:build`, `timeline_facade:build` and nothing
else, each with `cacheStrategy: hash`.

**It is hash-inert.** With the five written out explicitly instead of
`^:build`, `server:release` hashes `612677af` — the same value, a cache hit,
in a clean worktree at the final state. A control first established that a
comment-only edit to `server/moon.yml` leaves the hash untouched, so the hash
follows the resolved task and not the file.

**A depended-on project with no `build` task is skipped in silence.**
`timeline`'s artefact task was `package`, and `^:build` neither errored nor
warned; it simply omitted the project. A silent skip looks like an edge and is
not one, so the task is now named `build` — same command, `gleam export
erlang-shipment` — and the inherited edge reaches it.

### `server`'s `dependsOn: [pricing, timeline]` is deleted, and that is now required

Both entries existed to satisfy a rule moon applied to `project://` inputs —
an input could only name a *direct* project dependency — and outlived it when
adr-0006 deleted every such input. adr-0001 of the plugin measured them as
inert and kept them as an explicit cross-language statement.

Under `^:build` they are no longer inert. With them restored,
`server:release`'s deps gain `pricing:build` and its hash moves from
`612677af` to `54b7e8c0`; removing them returns it to `612677af`. The edge is
redundant — `pricing` is reached through `pricing_native` — and `timeline` is
silently dropped rather than being an edge at all. Keeping them would mean one
task's hash depends on how many entries a reader happened to leave in a list
that no longer describes anything.

Invalidation is unchanged without them, measured through the facades:

| edit | `pricing:build` | `pricing_native:build` | `timeline:package` | `timeline_facade:build` | `server:release` |
|---|---|---|---|---|---|
| clean tree | — | — | — | `89034519` | `612677af` |
| `timeline/src/timeline.gleam` | — | — | `893dfe44` | `79ee281e` | `e30e30fd` |
| `pricing/src/lib.rs` | `4d7f6eaa` | `ec81149e` | — | — | `87cda4c9` |

The same three shapes were measured against `server:test` in the repository
root before the templates were trimmed, and moved the same way.

No other project carries the same residue. `web → core-api-client`,
`mobile → web`, `core-api-client → server`, `e2e → server, web` and
`explorer → e2e` are each a direct edge, and the TypeScript toolchain syncs
project references from them. `pricing_native → pricing` is the Cargo edge Mix
cannot see, and it is now also what `^:build` resolves to.

### The Gleam edge is inferred, not written down

`timeline_facade/mix.exs` used to `Mix.raise` when `../timeline/build/otp` was
absent, which is the state of every clean checkout. An unevaluable manifest
infers nothing, so CI logged

```
elixir toolchain: cannot infer dependsOn for timeline_facade: timeline_facade:
/home/runner/work/baalbek/baalbek/timeline/build/otp does not exist.
```

on every cold run — the inference Stage 11 exists for, not running for the one
project whose dependency list only Mix can read. Five hand-written task edges
stood in for it: three `timeline:package` entries in `server/moon.yml`
(lines 68, 107 and 148) and two in `timeline_facade/moon.yml` (lines 26 and
57), which is seed.md §2's duplication restated at the task level.

The manifest now names the eleven applications whether or not the directory
exists — see the section on `$MIX_PATH_DEPS` below for why it must. Measured
with the directory deleted and moon's caches off, `moon project
timeline_facade` reports `timeline (production)` — the inferred edge — and
`timeline_facade:build` resolves to `['timeline:build',
'timeline_facade:deps']`. `mix deps.get` exits 0 with a
`missing dependency` warning per application, and `mix deps.compile boundary`
exits 0, so the `deps` tasks need no edge at all. All five edges are deleted:

| target | before | after |
|---|---|---|
| `server:deps` | `timeline:package` | — |
| `server:build` | 5 × `*:build`, `server:deps`, `timeline:package` | 5 × `*:build`, `server:deps`, `timeline:build` |
| `server:test` | + `server:bootstrap`, `timeline:bootstrap`, `timeline:package` | + `server:bootstrap`, `timeline:bootstrap`, `timeline:build` |
| `timeline_facade:deps` | `timeline:package` | — |
| `timeline_facade:build` | `timeline:package`, `~:deps` | `timeline:build`, `~:deps` |

`server` reaches `timeline:build` two ways now, and neither is written down:
transitively through `timeline_facade:build`, and directly because moon implies
a project dependency from `server:test`'s `timeline:bootstrap` edge, which
`^:build` then expands. The transitive path is the one to rely on; the implied
one would disappear with that bootstrap edge.

### Gleam splits what Gleam allows

`timeline:deps` runs `gleam deps download`, is keyed on `gleam.toml` and
`manifest.toml`, and declares `build/packages/**/*`. `test` and `build` take a
`deps:` edge on it.

Gleam 1.13 has no deps-only compile — `gleam build` compiles the dependencies
and the project together — so only the *download* is split, and the
dependencies are still compiled inside `test` and `build`. That costs less
than it sounds: from an empty `build/`, `gleam deps download` takes 1.4s and
`gleam build` 3.8s, because Gleam keeps its own package cache under
`~/.cache/gleam`. The Elixir split is worth 51s a project on the row above;
this one is worth about two seconds, and it exists so the two languages
describe their third party the same way.

## Consequences accepted

- **The saving is across runs, and a run that restores nothing is slower.**
  `.github/workflows/ci.yml` restores `.moon/cache` on a pull request,
  restore-only and keyed on the base SHA, and `main` writes it. That is the
  18.7× row. A run with nothing to restore — `main` itself, or a fork PR whose
  token cannot read the cache — pays the cold rows instead, 2.4× worse on
  `core:build`. Inside one such run the split still removes duplication: the
  third-party tree is compiled twice per project (dev and test) instead of
  three times, and `server`'s four compiling tasks share two trees instead of
  building four. That much does not pay for the serialisation it costs; only
  the restored cache does.
- **A `deps` archive is large.** `core:deps` archives 22 MB of sources and two
  compiled trees; `server:deps` holds 3,097 files under `build/dev/lib` alone.
  A local `.moon/cache` grows accordingly, and that is the price of restoring
  the sources alongside the artefacts.
- **`build/dev` and `build/test` are not what a developer's `mix` uses.**
  `mix test` by hand still compiles `_build/test`, so an app can be compiled
  three times on one machine. That was already true of `build/` under
  adr-0006; there are now two of them.
- **A project that redeclares a templated task inherits its own accumulation.**
  `inputs`, `deps` and `args` all merge. `args` in particular append, so a
  project that overrides `args` without `options.mergeArgs: replace` produces
  `["-lc", "mix test", "-lc", "…"]`, where `bash -lc` runs the first script and
  silently ignores the rest. Measured. No project in this workspace overrides
  `args`; `timeline_facade`'s boundary check became its own task rather than a
  replaced argument list for exactly this reason.
- **The plugin's contribution is lost if a project declares `deps` itself.**
  moon merges a plugin-provided task into an *inherited* one, but a task the
  project's own `moon.yml` declares replaces the plugin's version outright —
  and a single `deps:` edge is enough to do it. That is why the list arrives on
  `deps-list` and is read with `extends`. `server` and `timeline_facade` both
  declare `deps`, and both still get their list; without the indirection they
  would have run `mix deps.compile` with an empty variable.
- **Editing `.moon/tasks/elixir.yml` re-runs every Elixir task, and adding the
  file re-ran every task in the workspace.** `.moon/tasks/all.yml` declares
  `/.moon/tasks/*.yml` as an implicit input, so the glob's file set is part of
  every hash. moon additionally attaches `/.moon/tasks/elixir.yml` to the tasks
  that inherit from it, which is why a template edit does not touch `web`.
- **The first build after a clean checkout invalidated three tasks twice, and
  fixing the manifest is what stopped it.** While
  `timeline_facade/mix.exs` still raised without `build/otp`, the plugin read
  no list for that project on a clean checkout and `timeline_facade:deps` took
  its fetch-only fallback. `moon hash`
  puts the cost exactly: the cold `server:release` differs from the steady-state
  one in one field, `timeline_facade:build`'s hash; that differs in one field,
  `timeline_facade:deps`' hash; and that differs in one field, a missing
  `MIX_THIRD_PARTY_DEPS`. So those three tasks run once more, once, and are
  then stable. adr-0001 of the plugin measured this circularity as costing
  nothing when it only affected `dependsOn`; it now costs one extra run,
  because the same read feeds a hash. Writing the application list out is what
  removed it: the manifest answers the same before and after `timeline:build`,
  so there is no second answer to re-hash.
- **A `deps` task exists for every project whose language is `elixir`, whether
  or not it has third-party dependencies.** `timeline_facade` has one locked
  package, `boundary`, and its `deps` task takes 2.1s. That is not free, but a
  project-by-project exemption would be a list to maintain.
- **`server:release` still compiles the whole tree itself.** The plugin reads
  the dependency list at the default `MIX_ENV`, so there is no prod list to
  compile against, and `mix deps.compile cucumber` at `MIX_ENV=prod` would fail
  on a dependency that environment excludes. The release keeps its own
  `_build/prod`.
- **`bootstrap` is uncached, so it compiles the app on every run.** It runs
  `mix ecto.migrate`, which needs the app compiled, so it is the task that
  first populates `build/test/lib/<app>`. `test` then compiles nothing. The
  alternative — caching it — is what `timeline:bootstrap` already rejects: a
  warm cache against a fresh database is a real combination.

## Consequences accepted, continued

- **`$MIX_PATH_DEPS` is Mix's list, not the project graph's.** It carries every
  `path:` dependency's app name, including one that resolves to no moon
  project, because `mix deps.compile` has to be given the name either way. A
  path dep behind `only: [:dev]` would then be named at `MIX_ENV=test` and
  `mix deps.compile` would reject it; none exists in this workspace.
- **A computed manifest anywhere in a project's closure now fails that
  project.** The plugin reports no list at all rather than a short one, so a
  `mix.exs` that raises takes its consumers' lists down with it. That is the
  intended direction: a short list exits 0 and a missing one does not.
- **`timeline_facade` carries its Gleam application list by hand.** Eleven
  names in `mix.exs` instead of a `File.ls` over the shipment directory.
  `check_shipment!/0` fails the manifest when the two disagree, so drift is
  loud in every task that evaluates it, but the names are still written twice
  — once by Gleam's resolver into `timeline/manifest.toml`, once here.
- **Six tasks read the list through `extends: "deps-list"`.** `build` and
  `test` in the template, and the four `bootstrap` tasks. A seventh task that
  compiles and forgets the `extends` gets an unset variable, the guard skips
  the compile, and it fails on a cold tree with a missing app file — loudly,
  but only there.

## Alternatives considered

**One dependency tree shared by both environments.** Mix does not object, and
it would halve the `deps` task again. Rejected: the reason it does not object
is that it cannot tell, and a dependency that branches on `Mix.env()` at
compile time would then be wrong in one of the two suites with nothing to
report it.

**Declaring the compiled trees under `_build/`.** Rejected for adr-0006's
reason, unchanged: `_build` belongs to Mix, ElixirLS and the developer, and a
Moon cache restore must not write into it.

**Leaving `mix deps.get` in every compiling task.** Shipped first, and correct
in every case; rejected once measured, because 18 of the 24 invocations
existed to re-verify what moon's own key already guarantees, and each one in a
project with a git dependency re-cloned it.

**`--no-deps-check` everywhere.** Wrong until `$MIX_PATH_DEPS` became the
closure, and wrong in the direction that passes locally: a warm tree already
has the links, so the failure only appears on a cold checkout. Measured above.
It is now what every compiling task passes, and no project overrides it.

**Letting Mix run its own dependency check in the project that needs the
links.** Shipped first, as an empty `$MIX_DEPS_CHECK` in `timeline_facade`, and
it is what broke `main`. It fixes only the project that carries it: `server`
compiles the same eleven applications into its own tree and cannot take the
same branch, because it locks `ash_boundary` from git and Mix's check then
reports that dependency unavailable. Every such escape also restores a network
fetch the split exists to remove. The template no longer offers the variable.

**`mix deps.compile $MIX_PATH_DEPS --include-children`.** Mix resolves the
closure at the moment it matters, which is better information than any
graph-time list. Rejected on measurement: `--include-children` expands from
the path deps into their third-party children, so `ash_boundary` lands in the
command, and in the state moon's archive restores it fails with
`** (Mix) Cannot compile dependency :ash_boundary because it isn't available`.
Measured directly, with `server/deps/ash_boundary/.git` moved aside. Naming
only path deps is what keeps a git dependency out of the command.

**Reading the Gleam application list from `timeline/manifest.toml` instead of
writing it into `timeline_facade/mix.exs`.** That file is committed, so it
answers the same cold and warm, and Gleam generates it. Rejected: the list
`timeline_facade` needs is the *runtime* closure, and `manifest.toml` also
holds the dev-only packages `timeline/scripts/otp-closure.escript` filters out.
Naming `gleeunit` as a path dep would fail `mix deps.compile` in every
consumer, so the filter would have to be re-implemented in `mix.exs` in a
second language.

**Passing the dependency list as task arguments rather than task environment.**
Rejected on the merge order: inherited arguments come first, so the names would
land before the `mix` subcommand.

**Naming the list in each `moon.yml`.** It is 25 names for `core` and 42 for
`server`, duplicated from `mix.lock`, and seed.md §2 exists to stop exactly
that.

**A checker asserting the `deps` task never compiles a path dependency.**
Rejected for adr-0006's reason: the archive listing is the check, and the graph
should make the mistake impossible rather than detectable. What makes it
impossible here is that the names come from the lock, which cannot contain a
path dependency.

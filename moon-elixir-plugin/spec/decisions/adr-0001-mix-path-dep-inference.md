# ADR-0001: `dependsOn` between Elixir projects is inferred by asking Mix

**Status:** Accepted.
**Date:** 2026-09-07
**Stage:** 11

## Context

seed.md §2 asks for a moon WASM toolchain plugin that "parses `mix.exs` path
dependencies and infers `dependsOn` between Elixir projects, so the Mix
dependency graph is not duplicated by hand in YAML", and names a fallback
until it exists: declare `dependsOn` manually plus a CI script that diffs the
declaration against the manifest. Stage 1 built that script,
`check-deps-drift.py`. This stage builds the plugin and retires it.

The script worked. It also had the shape of every drift checker: two
descriptions of one fact, plus a third artefact whose whole job is to notice
when they disagree. It carried its own narrow regexes for both Elixir and
YAML, and a comment conceding that a manifest shape they did not recognise
would need the script widened alongside it.

PLAN.md bounds what the plugin is for, and the bound is load bearing:

> Inferring `dependsOn` from `mix.exs` path deps automates ordering, which
> was never the correctness problem — and it cannot see the Cargo path dep
> behind `pricing_native` or the build-output path deps behind
> `timeline_facade` at all.

The second half of that sentence turns out to be half right. The Cargo edge is
genuinely unreachable. The `timeline_facade` edge is not, once the plugin asks
Mix instead of reading the file.

## Decision

### The plugin asks Mix; it does not parse `mix.exs`

`mix.exs` is Elixir source, evaluated by Mix, so a dependency list can be
*computed* — `timeline_facade/mix.exs` maps `File.ls` over
`../timeline/build/otp` and takes one path dep per OTP application. Any parser
short of an Elixir implementation reads such a manifest wrongly or not at all.

So `extend_project_graph` runs **one** `elixir` process for the whole
workspace. It passes an embedded Elixir program (`src/mix.rs`'s
`READ_MANIFESTS_EXS`) and one `<id>=<source>` argument per project that has a
`mix.exs`. The program calls `Mix.Project.in_project/3` on each, reads
`Mix.Project.config()[:deps]`, and prints one JSON line: for every `path:`
dependency, the app name, the path resolved and made workspace-relative, and
whether `only:` excludes `:prod`. `src/inference.rs` then maps each path onto
the project that owns it — the project rooted exactly there, else the nearest
one rooted above it — and drops self-edges, duplicates, absolute paths and
paths that climb out of the workspace.

This is the mechanism moon's own first-party Go toolchain uses (`go list`),
and it is the mechanism this repository has now chosen three times: read
Playwright's `--list --reporter=json` rather than parse spec files
(`../../explorer/spec/decisions/adr-0004-the-project-graph-is-more-than-the-moon-yml-files.md`),
verify against `moon hash` rather than reconstruct moon's hashing rule
(`../../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md`), and
now ask Mix rather than lex Elixir. The tool that owns the fact answers for
it.

`moon_pdk` permits this: it re-exports `warpgate_pdk`, whose `exec` /
`exec_captured` call the host's `exec_command` function. Verified from inside
`extend_project_graph` under WASM, not assumed — `tests/extend_project_graph_test.rs`
drives the compiled `wasm32-wasip1` artifact through moon's plugin harness and
a real `elixir` subprocess.

### The plugin depends on nothing else in this workspace

seed.md:161 says this project "may live in its own repo". So copying
`moon-elixir-plugin/` into an empty repository must lose nothing:

- `moon.yml` declares `Cargo.toml`, `Cargo.lock`, `src/**/*`, `tests/**/*`
  and no path outside its own directory, and no `dependsOn`.
- Every test expectation comes from `tests/__fixtures__/projects`. The
  fixtures carry a literal path-dep list, a project with none, a dependency
  list built by `File.ls` at evaluation time, a manifest that raises, and one
  whose paths escape the workspace or name itself.
- No test asserts on a sibling project. A suite that read this repository's
  real `mix.exs` and `moon.yml` files was considered and rejected: it would
  make the crate unpublishable, re-run the plugin's suite whenever any
  project's `moon.yml` changed, and — in the form that was tried — guard
  another language's manifest in a different project, which is not this
  plugin's business.
- The fixture tree avoids the name `build/`, because this workspace's
  `hasher.ignorePatterns` excludes `**/build/**` from task inputs and silently
  dropped two fixture files from the suite's hash. A plugin that depends on
  the host workspace's hasher settings is not standalone.

That the inference is right *for this workspace* is demonstrated by the
workspace itself, every time it builds: `moon project server` lists the five
Elixir edges as `(production)`, and with `inferRelationships: false` the same
edges reappear as `core (build via task core:build)`. That is a better proof
than a Rust assertion, because it exercises the real graph.

### An unreadable manifest warns; it never fails the graph

A manifest that raises is reported against that project alone, with Mix's own
message, and infers nothing:

```
elixir toolchain: cannot infer dependsOn for timeline_facade: timeline_facade:
/…/timeline/build/otp does not exist.
Run `moon run timeline:package` (or bash timeline/scripts/package-otp.sh) first.
```

Other projects in the same run are unaffected — verified, the failure does not
poison the `elixir` process.

**A missing `elixir` has to be probed for, not attempted.** The host validates
the command before spawning it and *aborts the guest call* when it is absent,
which no `Result` in the plugin can catch:

```
Error: plugin::wasm::failed_function_call
  × Command or script elixir does not exist. Unable to execute from plugin.
```

Measured: that aborts the project graph, so `moon project`, `moon query
projects` and even `moon run web:test` exit 1 — every command in the
workspace, coupled to the BEAM toolchain by a plugin that only reads
manifests. So `read_manifests` calls `moon_pdk`'s `command_exists` first,
which shells out to `which` (or `Get-Command` on Windows) and therefore
cannot abort. With Elixir off `PATH`, `moon project server` now prints
`elixir toolchain: cannot read mix.exs dependencies: \`elixir\` is not on
PATH`, lists every edge as `(build via task …)`, and exits 0.

Warning rather than erroring is deliberate and it is the one place this
replacement is **less strict than the script it replaces**. seed.md §2 asks
that drift "fails the build rather than corrupting affected-detection", and a
warning does not fail the build. The reason is measured: an error returned
from `extend_project_graph` fails the *project graph*, and therefore every
moon command, including the ones that would fix the cause. The previous
implementation read each manifest in Rust and propagated the read error, so
invalid UTF-8 in `core/mix.exs` produced

```
Error: plugin::wasm::failed_function_call
  × stream did not contain valid UTF-8
```

and `moon query projects`, `moon ci` and `moon run moon-elixir-plugin:build`
all exited 1 against a message that named no file. Asking Mix removes that
failure mode rather than merely surviving it — the same corrupted manifest now
gives `elixir toolchain: cannot infer dependsOn for core: invalid encoding
starting at <<255, 254, …>>` and every command still exits 0 — because the
plugin no longer reads manifest bytes at all; it checks that `mix.exs` exists
and lets Elixir report on the contents. The degradation is survivable because
the task `deps` on output-declaring tasks (adr-0006) still carry ordering and
hashing.

### `timeline_facade`'s bootstrap circularity, and what it costs

`timeline_facade/mix.exs` raises unless `../timeline/build/otp` exists, and
that directory is produced by `moon run timeline:package` — a task that cannot
run until the project graph is built. Asking Mix therefore reads that manifest
in a built tree and not in a clean one, so the inferred graph differs between
the two.

Measured, that difference costs nothing. With the build output moved aside and
the graph rebuilt, `moon project timeline_facade` degrades from
`timeline (production)` to `timeline (build via task timeline:package)`, and
`moon query tasks --affected --downstream deep` for
`timeline/src/timeline.gleam` is **byte-identical** in both states:

```
{'core-api-client': ['build'], 'e2e': ['test'],
 'mobile': ['build','build-android','build-ios'],
 'server': ['image','openapi','release','test'],
 'timeline': ['bootstrap','package','test'],
 'timeline_facade': ['build','test'],
 'web': ['build','image','test']}
```

So `timeline_facade/moon.yml`'s hand-written `dependsOn: ["timeline"]` is
**deleted**. It described a Mix path dep, which seed.md §2 says must not be
duplicated in YAML, and the fallback path is the task dependency rather than
the declaration.

## Consequences accepted

- **A redundant or false hand-written `dependsOn` is no longer checked, and
  this is a real reduction in coverage.** `check-deps-drift.py` diffed in both
  directions. The dangerous direction — a Mix path dep that no `dependsOn`
  declares, which under-invalidates and silently corrupts affected-detection —
  is now *eliminated* rather than checked: inference makes it an edge whether
  or not anyone typed it. The other direction — a `dependsOn` naming an Elixir
  project that no `mix.exs` backs — remains expressible, and no gate fails on
  it. Three reasons that is accepted rather than replaced. It over-declares,
  and over-declaration is safe over-invalidation, never a stale pass. It is
  indistinguishable in kind from the legitimate hand-declared cross-language
  edges (`pricing_native → pricing`), so no tool can judge the intent. And
  the plugin cannot see it at all: `ExtendProjectGraphInput` carries
  `project_sources` and nothing about declared dependencies.
  The rejected repairs are below.
- **Stage 10's explorer reports such an edge, as a finding rather than a
  gate.** A phantom `core → billing` added to `core/moon.yml` appears in
  `explorer:generate`'s model as
  `{"from":"core","to":"billing","strength":"declared-only","hashingTaskDeps":[]}`
  and is listed under the `declaration-only-edges` gap. That is the same
  report-don't-fail asymmetry PLAN.md endorses for capability coverage, and it
  is weaker than the drift check in a specific way: the classification is
  about *hashing*, not about provenance, so a phantom edge that happens to be
  reachable another way is hidden. `server → pricing` is classified
  `transitive` for exactly that reason, so a phantom edge coinciding with a
  transitive path would not be listed.
- **A phantom `dependsOn` that closes a cycle fails every moon command, and
  the message points at the wrong file.** This is the sharp end of the two
  bullets above: over-declaration is usually safe, but not when it makes the
  graph invalid. Adding `{:server, path: "../server"}` to `core/mix.exs` gives
  `project_graph::would_cycle × Unable to create project graph, adding a
  relationship from server to core would introduce a cycle`. Correct — Mix
  would reject it too — but it names the *inferred* direction rather than the
  `mix.exs` or `moon.yml` line to edit, mentions neither this plugin nor Mix,
  and the `via` provenance the plugin attaches (`mix.exs path dep :server`) is
  surfaced nowhere: `moon project` prints only the scope, and
  `moon project-graph --json` reports `via: null` for inferred edges.
- **A path dep behind a `MIX_ENV` conditional is missed silently, and that is
  a hole in the direction claimed eliminated.** The `elixir` process runs at
  the default `MIX_ENV=dev`, so
  `if Mix.env() == :prod, do: [{:identity, path: "../identity"}], else: []`
  infers nothing, while the same manifest evaluated at `MIX_ENV=prod` yields
  `[identity: [path: "../identity"]]`. Both measured. The retired regex would
  have matched the literal and caught it. Reading every environment would mean
  one BEAM run per environment and a union of the results, which changes what
  `dependsOn` *means*; scoping by `only:` is already handled, and a
  `Mix.env()` conditional on a *path* dep does not occur in this workspace.
  Recorded rather than fixed.
- **One `elixir` process costs about 400 ms, on a project-graph rebuild
  only.** `moon query projects`, five runs each: 610 ms median with the plugin
  when the graph is rebuilt against 210–310 ms without; 210 ms against 211 ms
  once the graph is cached. moon caches the project graph keyed on the
  `input_files` the plugin returns — every `mix.exs` it read — so the shell-out
  happens when a manifest's content changes and not otherwise. One process for
  six manifests is what makes this affordable; six BEAM startups measured
  about 1.9 s.
  Note when measuring this: `moon query projects` in this sandbox is bimodal
  at roughly 210 ms or 310 ms whether or not the plugin is loaded, so a
  five-run median can show a 100 ms difference that is entirely noise. Compare
  minima over twenty runs, and separate the graph-rebuilt case from the
  graph-cached one.
- **The plugin needs `elixir` on `PATH` while the graph is built, and Elixir
  1.18+ or OTP 27+.** proto already installs it for every Elixir task, so this
  adds no tool to the workspace, but it does put it on a new code path. The
  version floor is the JSON encoder (`JSON` in Elixir 1.18, `:json` in
  OTP 27); the program tries both and says which it needs if neither is there.
  `mix deps.tree` was not used: it needs dependencies fetched, which is a
  far heavier prerequisite than evaluating `project/0`.
- **The compiled artifact is committed, and only the build task catches a
  stale one.** `plugin/moon_elixir_plugin.wasm` is in git, which no other
  project's build output is, because moon loads the file while building the
  project graph — without it every moon command fails outright, including the
  `moon run moon-elixir-plugin:build` that would produce it. There is no
  bootstrap order that works.
  `explorer`'s adr-0004 rejected committing its generated model because "a
  committed model can be stale, and a stale model is indistinguishable from a
  fresh one". The objection applies here, and neither obvious answer to it
  holds up:
  1. `moon ci` does rebuild the artifact, but nothing compares the rebuilt
     bytes with the committed ones, so `moon ci` exits 0 on a stale commit.
  2. `git status` only shows the divergence *after* someone has run the build
     locally; a `src/` change committed without running it leaves a clean
     tree. And a rebuild does not change what moon reports either:
     `.moon/cache/states/workspaceGraphStateV1.json` keys the graph cache on
     `pluginInputPaths` — the manifests — so its `lastHash` was byte-identical
     (`a699a778…`) before and after a deliberate behaviour change was compiled
     in, and `moon project server` kept reporting the old inference until a
     `mix.exs` changed content. Editing `src/` is invisible from both
     directions at once.
  So `moon-elixir-plugin:build` ends in `git diff --exit-code -- plugin/`,
  which fails the task whenever the compiled artifact differs from the
  committed one. That is the whole mitigation, and it is worth naming what it
  does not cover: it fires only when the task runs, so a `src/` edit committed
  without running the build is caught by the next `moon ci` that selects the
  task rather than at the moment of the commit.
  Verified alongside it: the build is reproducible. A clean rebuild in a fresh
  `CARGO_TARGET_DIR` produced a byte-identical `moon_elixir_plugin.wasm`
  (`sha256 cff79dec…`), so "does the committed artifact match the source" is a
  decidable question and the guard above is a sound way to ask it.
- **`server`'s two surviving hand-written edges are inert, and kept anyway.**
  Removing `pricing` and `timeline` from `server/moon.yml`'s `dependsOn`
  leaves `moon query tasks --affected --downstream deep` byte-identical for a
  `pricing` or a `timeline` change: `pricing` is reached through
  `pricing_native`, `timeline` through `server`'s own `deps` on
  `timeline:package`. They stay as the explicit cross-language statement
  seed.md §3 asks for, not because affected-detection needs them, and
  `server/moon.yml` now says so. The previous comment claimed `moon ci` needed
  them, which is false.
- **This is a maintenance win, not a correctness one.**
  `moon query tasks --affected --downstream deep` for `core/lib/core.ex` is
  byte-identical with `inferRelationships: true` and `false`, because every
  Elixir path-dep edge is already carried by a task `deps` entry on an
  output-declaring task (adr-0006), which is what folds an upstream change
  into a downstream hash. `dependsOn` orders and scopes; it does not
  invalidate. What the plugin removes is the pair of hand-maintained lists,
  the script that diffed them, and the class of bug where a future Elixir
  app's path dep never reaches the graph because nobody typed it.
- **One edge is outside what Mix can see, and stays hand-declared.**
  `pricing_native → pricing` is a Cargo path dependency in
  `native/pricingnative/Cargo.toml`. Mix never evaluates that file, so no
  amount of asking Mix will surface it.
- **`versionFromPrototools` is inert here.** It is set to `"asdf:elixir"`
  rather than PLAN.md's literal `true`, because `true` resolves against the
  toolchain's own id and this workspace has no plain `elixir` entry in
  `.prototools` — proto installs Elixir through its asdf backend. Measured
  inert either way: every Elixir task declares `toolchain: "system"`, so
  editing `.prototools` from `1.20.2` to `1.20.1` left `core:build`'s hash at
  `b0c67c50`, and `true` in place of `"asdf:elixir"` also left it there.
  Neither spelling errors. Named correctly so it starts working if this plugin
  ever grows tier-2 dependency installs.
- **The dependency set needed two `Cargo.lock` pins to resolve.**
  `system_env 0.10.2` moved to `schematic 0.20` in a patch release while
  `moon_config 2.1.2` still uses `0.19.7`, which puts two incompatible
  `Schematic` traits in one graph and fails to compile
  (`the trait bound SystemOS: Schematic is not satisfied … there are multiple
  different versions of crate schematic_types`). `system_env` is pinned to
  `0.10.1` and `version_spec` to `0.11.2`, matching what `moonrepo/plugins`
  locks. Both are transitive, so the pin lives only in `Cargo.lock` and
  `cargo update` will reintroduce the break; nothing asserts the versions.
- **The plugin API is real but young.** Built against moon 2.5.4 with
  `moon_pdk 2.1.1` / `moon_pdk_api 2.1.3`. The functions used are the ones the
  first-party Go and Rust toolchains use, so they are exercised upstream — but
  `ExtendProjectOutput` is a plain data contract with no stability guarantee,
  and a `moon` upgrade may need the crate rebuilt.

## Alternatives considered

**Hand-write an Elixir parser.** A lexer plus a dependency-list parser that
reads literal `{:app, path: "…"}` tuples and reports anything else as
unreadable. Written and measured before this decision was taken, at about 890
lines. Rejected on two findings.

It produces a silently wrong graph for a realistic manifest. Requiring
`deps/0`'s body to begin with `[` and reading to the matching `]` ignores
whatever follows, so a cons tail is caught but an *append* is not:

| manifest body | that parser | truth |
|---|---|---|
| `[{:core, path: "../core"} \| computed()]` | reports "computed" ✓ | computed |
| `[{:core, path: "../core"}] ++ computed()` | infers `core`, silent ✗ | `core` + computed |
| `[a, b] \|> Enum.reject(...)` | infers both, silent ✗ | a subset |

`hex_deps() ++ path_deps()` passes, because the computed half comes *first*;
reversing the operands defeats it. Asking Mix reads the same manifest as
`billing` plus `identity`, verified.

Reporting a computed list as unreadable is also the wrong answer, not a safe
one. It leaves `timeline_facade` with no edges, which then needs an
acknowledgement list in `.moon/toolchains.yml`, a hand-written `dependsOn` in
`timeline_facade/moon.yml`, and a test policing that the two stay in step —
three artefacts that exist only to describe a manifest Mix can simply read.

Whether such a parser can be made robust is not the question: heredocs
containing `defp deps do`, regex sigils with escaped braces, charlists with
apostrophes, `?"` and `?{` char literals and literal `#{}` in strings all
survived probing. A hand-written parser of another language's syntax is
unmaintainable regardless, and its failure mode is a confidently wrong graph.

**Keep `check-deps-drift.py` and run it alongside the plugin.** Rejected as
the failure mode this stage exists to remove: the checker only has something
to check if the hand-written lists stay, and the lists are the duplication.

**Re-home the drift check so the other direction stays covered.** Three forms
were considered for catching a `dependsOn` that no `mix.exs` backs. A Rust
test in this crate — rejected, it is the repo-invariant checker that made the
crate unpublishable, and the version that existed parsed YAML with
`lines().take_while(|l| l.starts_with("  - "))`, which two realistic
spellings walked straight past: `dependsOn: ["core"]` and a comment as the
first item of the list. Both were verified to add a real edge that the test
passed on, and the second is a case the deleted Python regex *did* catch. A
plugin-side check — impossible, the input carries no declared dependencies.
A new `root:` task — rejected as re-adding `check-deps-drift.py` under a new
name. So the gap is recorded as a consequence instead, on the ground that its
direction over-declares rather than under-declares.

**One `elixir` process per project.** Rejected on measurement: about 320 ms of
BEAM startup each, roughly 1.9 s for six, against 410 ms for one process
doing all six.

**`mix deps.tree` or `mix deps`.** Rejected: both need dependencies fetched,
so the graph build would depend on `mix deps.get` having run. Evaluating
`project/0` needs nothing but the manifest.

**Emit a project alias from `mix.exs`'s `app:` name.** The Rust and Go
toolchains do. Rejected as gold-plating: every OTP application name in this
workspace already equals its directory name, so every alias would duplicate
an id.

**Implement tier-2 `install_dependencies` so moon runs `mix deps.get`.**
Rejected as out of scope for the stage and for seed.md §2, which asks for
manifest parsing and dependency inference. proto owns the Elixir install and
each project's task already runs `mix deps.get`; taking that over would
change how eleven tasks execute in a stage about how the graph is built.

**Do not commit the WASM; build it in CI before any other moon command.**
A pre-moon bootstrap step (`cargo build` before `moon`) was rejected because
it makes `moon` alone insufficient to work in the repo, which is the property
the whole workspace is built on. What committing costs instead, and the
`git diff --exit-code` guard that holds it, are above.

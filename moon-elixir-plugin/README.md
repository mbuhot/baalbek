# moon-elixir-plugin

A moon toolchain plugin that reads each Elixir project's `mix.exs`: it infers
`dependsOn` from the path dependencies, and hands the third-party dependency
list to the project's tasks.

Rust compiled to `wasm32-wasip1`. It reads the dependency lists by asking Mix,
not by parsing `mix.exs`, so a list that is computed at evaluation time is
resolved rather than reported as unreadable.

## Requirements

- moon 2.5+
- `elixir` on `PATH` while the project graph is built, and Elixir 1.18+ or
  OTP 27+ (for a JSON encoder). Nothing needs to be compiled or fetched
  first — only the manifest is evaluated.

## What it does

`register_toolchain` tells moon that `mix.exs` is a manifest, `mix.lock` a
lockfile, and `deps/` a vendor directory, and claims `language: elixir`.

`extend_project_graph` runs one `elixir` process for the whole workspace. It
calls `Mix.Project.in_project/3` on every project that has a `mix.exs`, reads
`Mix.Project.config()[:deps]`, and turns each `path:` dependency into an edge
onto the project that owns that path — the project rooted exactly there, else
the nearest one rooted above it, so a path dep pointing into another project's
build output still resolves to that project. `only:` without `:prod` makes the
edge a development dependency.

Self-edges, duplicates, absolute paths, and paths that climb out of the
workspace are dropped: none is an edge moon can express.

The same process attaches two dependency lists to a `deps-list` task, each
space-separated, sorted and deduplicated:

| variable | contents |
|---|---|
| `$MIX_THIRD_PARTY_DEPS` | every name in `mix.lock`, read through `Mix.Dep.Lock.read/1` |
| `$MIX_PATH_DEPS` | every `path:` dependency's app name, as Mix resolved it |

```yaml
tasks:
  deps:
    extends: "deps-list"
    command: "mix"
    args: ["deps.compile", "$MIX_THIRD_PARTY_DEPS"]
    inputs: ["mix.exs", "mix.lock"]
```

The lock names the whole third-party tree, transitive entries included, and
never a `path:` dependency — which is what lets a task compile the
third-party half of a build without touching the first-party half. The path
list is the other half, for a task that has to name them instead: `mix
compile --no-deps-check` skips the step that compiles a path dependency into
the build path, so a consumer that skips the check has to run
`mix deps.compile $MIX_PATH_DEPS` itself. It is Mix's list, not the project
graph's — a path dependency resolving to no moon project is still named.

`extends` is how a consuming task reads either: a task a project's own
`moon.yml` declares replaces the plugin's version of that task, and it takes
only a `deps:` edge to do it, so the lists arrive on a task nothing else has
a reason to declare.

A lockfile Mix cannot read — missing, conflicted, not a map — is an empty list
rather than an error. A manifest that raises delivers no list at all.

## What it does not do

- **It orders, it does not invalidate.** `dependsOn` decides what runs first
  and what `moon ci` considers affected. A source change reaching a
  dependent task's hash is a separate mechanism — see moon's task `deps` and
  declared `outputs`. moon's `^:build` scope turns the inferred edges into
  hash edges, which is how a consumer gets both from one declaration.
- **It defines no task.** `deps-list` carries the list and runs `noop`. What
  compiles the dependencies, where it writes, and what it declares as
  `outputs` are the workspace's decisions, not this plugin's.
- **It runs no build and manages no versions.** It evaluates `project/0` and
  nothing else. Installing Elixir, fetching dependencies and compiling stay
  with whatever already does them.
- **It cannot see a non-Mix edge.** A Rustler NIF's Cargo path dependency, for
  instance, is invisible to Mix and therefore to this plugin. Declare those by
  hand.
- **It does not support umbrella projects.** Only `path:` becomes an edge. An
  umbrella child is declared `{:sibling, in_umbrella: true}`, with no `path:`
  key, so it is dropped silently. Umbrella is the dominant Elixir multi-app
  layout and this is the most likely reason the plugin infers nothing for a
  workspace that looks like it should work.
- **It reads one Mix environment.** The `elixir` process runs at the default
  `MIX_ENV=dev`, so a path dep behind `if Mix.env() == :prod` is not seen.
- **It cannot read a manifest that raises.** A `mix.exs` needing something no
  build has produced yet infers nothing for its own project, warns with Mix's
  own message, and leaves every other project unaffected.
- **It infers nothing when `elixir` is missing.** The binary is probed before
  it is called, so a workspace with no Elixir installed gets one warning and
  keeps working; every `dependsOn` is then whatever the `moon.yml` files say.

## Settings

```yaml
elixir:
  plugin: "file://./path/to/moon_elixir_plugin.wasm"
  inferRelationships: true   # default; false leaves every dependsOn hand-written
```

## Working on it

```sh
moon run moon-elixir-plugin:test     # builds the WASM, then runs the suite
```

Every test expectation comes from `tests/__fixtures__`, so the suite proves
the inference rule rather than any particular workspace's shape. The project
declares no input outside its own directory and depends on no other project.

`plugin/moon_elixir_plugin.wasm` is committed, unlike ordinary build output:
moon loads it while building the project graph, so a missing file fails every
moon command — including the one that would rebuild it. It is committed with
`plugin/moon_elixir_plugin.provenance`, a record of the source it was built
from, and `moon run moon-elixir-plugin:build` fails whenever the two disagree.
After editing `Cargo.toml`, `Cargo.lock`, `src/` or `scripts/`:

```sh
bash scripts/build.sh --accept   # rebuild, re-record, then commit both files
```

That gate is the only thing that catches a stale artifact, because one nobody
rebuilt leaves a clean `git status`, and a rebuilt one does not change what
moon reports until the project-graph cache is invalidated by a manifest
change. It asserts provenance rather than byte-identity, because rustc emits
different wasm from an x86_64 host than from an aarch64 one. All measured, in
`spec/decisions/adr-0001-mix-path-dep-inference.md` and
`spec/decisions/adr-0002-the-committed-wasm-gate-asserts-provenance.md`.

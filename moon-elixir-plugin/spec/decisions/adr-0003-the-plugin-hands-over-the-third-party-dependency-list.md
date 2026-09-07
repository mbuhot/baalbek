# ADR-0003: The plugin hands over the third-party dependency list

**Status:** Accepted. Extends adr-0001.
**Date:** 2026-09-07
**Stage:** mid-build, after Stage 12's first full-graph CI run

## Context

adr-0001 has the plugin ask Mix for each project's dependency list and turn
every `path:` entry into a `dependsOn` edge. The other half of that list — the
dependencies Mix resolves from a registry or a git ref — was read and thrown
away.

The consuming workspace now needs it. Its Elixir projects compile their
third-party tree in a task of its own, keyed on `mix.exs` and `mix.lock`, so
that a first-party edit does not recompile Ash
(`../../spec/decisions/adr-0010-third-party-deps-compile-in-their-own-task.md`).
That task has to name the dependencies it compiles: a bare `mix deps.compile`
compiles the path dependencies too, and `server` has five of those while
`timeline_facade` has eleven. Naming them in each `moon.yml` would duplicate
`mix.lock`, which is the duplication seed.md §2 asks this plugin to remove.

This ADR was first written with a second list, the `path:` closure, alongside
the locked names. That list existed only because the consuming workspace could
not let Mix run its own dependency check; the section below records why, and
why it is gone.

## Decision

### The list comes from the lock, not from `deps`

Inside the same `Mix.Project.in_project/3` call, the program now also runs
`Mix.Dep.Lock.read/0` and reports its keys as strings, sorted.

`Mix.Project.config()[:deps]` was the obvious source and is the wrong one: it
names only the *direct* dependencies. `mix deps.compile ash` does not compile
`spark`, `crux` or `postgrex`, so the transitive half of the tree would fall
through to whatever ran next. The lock is the whole tree — 25 entries for
`core` where the manifest lists 5, 42 for `server` — and it can hold nothing
else, because Mix never writes a `path:` dependency to it. Verified against
every manifest in the consuming workspace: `timeline_facade`, whose manifest
computes eleven path dependencies, locks exactly one name, `boundary`.

That property is what makes this safe rather than merely convenient. The task
consuming the list cannot be handed a first-party dependency by mistake.

`Mix.Dep.Lock` is `@moduledoc false`. Reading the file directly was the
alternative, and it is the thing adr-0001 spends most of its length arguing
against: the lock is Elixir source, and Mix's reader already handles a merge
conflict, a syntax error and a non-map by returning `%{}`. A private module
that has existed since Mix did is a better bet than a second parser.

### The list travels on a task of its own

`extend_project_graph` attaches the list to a `deps-list` task as
`$MIX_THIRD_PARTY_DEPS`, space-separated. The task carries no command, so moon
gives it `noop`.

It is not attached to the task that compiles anything, and that is measured
rather than stylistic. moon merges a plugin's task into an *inherited* one —
a `.moon/tasks/*.yml` declaration keeps its command and gains the plugin's
environment — but a task the project's own `moon.yml` declares **replaces** the
plugin's version of it outright. A single `deps:` edge in a project file is
enough:

```
# project declares `deps` with one added edge
env: None
# same task, declared only in .moon/tasks/elixir.yml
env: {'MIX_THIRD_PARTY_DEPS': 'ash ash_boundary ash_postgres …'}
```

Two projects in the consuming workspace have to add such an edge. So the list
arrives on a task nothing has a reason to declare, and the compiling task reads
it with `extends: "deps-list"`, which does merge and survives a project-level
override.

An environment variable rather than arguments, for the same kind of reason:
inherited arguments are appended *before* the project's own, so the dependency
names would land ahead of the `mix` subcommand.

### The `path:` names are not handed over

A second list, `$MIX_PATH_DEPS`, was shipped alongside the locked names and is
now deleted. It carried each project's `path:` closure, because
`--no-deps-check` — which the consuming workspace needed while it locked
`ash_boundary` from git, a dependency whose `.git` moon's archiver will not
carry — also skips the step that compiles a `path:` dependency into the build
path. Direct entries were not enough: `mix deps.compile timeline_facade` links
`timeline_facade` and does not descend, so `server` compiled against the eleven
Gleam applications behind that facade with none of them loaded, and the program
had to walk each manifest's path deps recursively.

`ash_boundary` 0.1.0 is published, and Mix verifies a Hex dependency through
`deps/<name>/.hex`, a dotfile the archiver carries. So the consumer runs plain
`mix compile` and `mix test`, Mix's own check resolves the path-dep closure at
the moment it matters, and no graph-time list is needed. The recursive walk,
its memoisation, and the `PathDep` closure field are gone;
`../../spec/decisions/adr-0010-third-party-deps-compile-in-their-own-task.md`
records the measurement.

The **direct** `path:` entries are still read. They are what `dependsOn` is
inferred from, which is adr-0001's decision and unaffected by any of this.

### An entry is emitted for every readable manifest

adr-0001 emitted an `ExtendProjectOutput` only for a project with at least one
inferred edge. Now every project whose manifest evaluates gets one, because a
project with no path dependencies still has a dependency list — and a project
with no *locked* dependencies has an empty one, which is a fact worth stating.

The three cases the consuming task distinguishes:

| manifest | lock | `$MIX_THIRD_PARTY_DEPS` |
|---|---|---|
| evaluates | readable | the names |
| evaluates | missing, conflicted, or not a map | empty |
| raises | not read | unset |

Unset is the signal that the plugin could not read the manifest at all. It is
distinguishable from empty, and the consuming task treats the two differently:
`../../spec/decisions/adr-0010-third-party-deps-compile-in-their-own-task.md`
records why compiling nothing is the safe answer there and compiling everything
is not.

## Consequences accepted

- **A project with no `deps-list` consumer gets an inert `noop` task.** Any
  moon workspace loading this plugin gains one task per Elixir project whether
  or not anything reads it. Measured as harmless — `moon project core` lists it
  and it does nothing — but it is a task in the graph that exists for a
  convention the plugin cannot enforce.
- **The plugin now depends on the lockfile's shape as well as the manifest's.**
  It reads the lock through Mix, so a format change is Mix's to absorb, but a
  workspace that keeps its lock somewhere unusual is only handled to the extent
  `Mix.Project.config()[:lockfile]` is honoured — which is how
  `Mix.Dep.Lock.read/0` finds it, so it is.
- **An unreadable lock is silent.** `Mix.Dep.Lock.read/0` returns `%{}` for a
  missing file, a merge conflict, a syntax error or a non-map, with no way to
  tell those apart. The plugin reports an empty list and no warning. The
  fixture `unlockable` pins the behaviour: a truncated lock yields `Some("")`
  while the project keeps its inferred `dependsOn`. The alternative — treating
  it as a manifest failure — would void the edges too, for a file that
  `mix deps.get` will report on far more clearly.
- **The list is read at one `MIX_ENV`.** Unchanged from adr-0001 and now more
  visible: the lock is environment-independent, but a consumer compiling at
  `MIX_ENV=prod` cannot use this list, because it names dependencies that
  environment excludes. `server`'s release task compiles its own tree for
  exactly this reason.
- **The crate keeps its zero workspace dependencies.** The expectations come
  from two fixture lockfiles (`app`, `lib`) and one deliberately unreadable one
  (`unlockable`). Nothing asserts on the host workspace's manifests. 26 tests,
  `--no-default-features` for the rule and the compiled `wasm32-wasip1`
  artifact for the plugin functions. The `consumer` fixture, whose path dep
  raised, went with the closure it existed to cover.
- **The list is still the answer from before any task ran.** A `mix.exs` that
  computes its dependency list from a directory some task writes answers one
  way on a cold project graph and another on a warm one, and both the inferred
  `dependsOn` and this list inherit that.
  `../../spec/decisions/adr-0010-third-party-deps-compile-in-their-own-task.md`
  records what the consuming workspace does about it.
- **A consumer taking a first-party dependency from git brings the second list
  back.** moon's archiver still refuses a nested `.git/`, so a workspace in
  that position needs `--no-deps-check` and therefore needs to name its path
  deps again. The plugin no longer offers to.

## Alternatives considered

**Emit the whole `deps` task from the plugin** — command, inputs and outputs
included, the way moon's first-party toolchains emit tasks. Rejected on
degradation: a project referencing `~:deps` from its `build` task would then
fail its task graph whenever the plugin emitted nothing, which is the state a
clean checkout is in for a manifest that needs a build output to exist. The
declaration stays in the workspace, where a missing list fails one task
instead.

**Attach the list with `extends` from the plugin side.** Symmetrical, and it
inverts the failure: `extends` on a task that does not exist is
`task_builder::unknown_extends`, which fails every moon command. Declaring
`deps-list` in the workspace as well keeps the reference resolvable when the
plugin is silent.

**Report the direct dependencies and let the consumer resolve the transitive
closure.** That is re-implementing Hex's resolver against the lock, in YAML or
in a script, to produce what the lock already contains.

**Keeping the `path:` closure for a consumer that still wants it.** It is 224
lines of plugin, test and fixture for a list no consumer of this plugin needs
once its dependencies are all fetchable, and a list that is wrong by
construction the moment a manifest computes itself from a build output.
Rejected: the plugin should not carry a workaround for one workspace's
unpublished dependency.

# ADR-0001: The explorer's data comes from the live graph, and cannot be cached

**Status:** Superseded by [adr-0004](adr-0004-the-project-graph-is-more-than-the-moon-yml-files.md)
**Date:** 2026-09-07
**Stage:** 10

## Context

seed.md §9 asks for an explorer "regenerated from the same inputs as the
build, so it cannot drift". That sentence is the whole requirement. A
diagram that is redrawn by hand, or regenerated from a snapshot someone
committed, has already failed — the value of the thing is that it is
correct by construction rather than by diligence.

The three inputs seed.md names are unusual in different ways.

`moon project-graph --json` and `moon task-graph --json` are not files. They
are moon's own view of the workspace, computed from every `moon.yml` and
from `.moon/`. No task produces them.

Git history is not a file either, and nothing in the working tree changes
when a commit lands.

`capabilities.yml` is the one ordinary input, and the one that can rot: it
is hand-written, and nothing in the compiler or the test suite notices when
a project it names disappears, or when a new project it does not name
arrives.

## Decision

**The generator shells out to `moon`.** It runs `moon project-graph --json`
and `moon task-graph --json` from inside `explorer:generate`, which is
itself a moon task. Nested invocation was the main risk and it works:
both are read-only queries against the project cache. Parsing the
`moon.yml` files directly was rejected — it would re-implement task
inheritance, toolchain aliasing and dependency resolution, and the
re-implementation would be the thing that drifts.

**The `moon.yml` files are declared as `inputs`.** `explorer:generate`
lists `/*/moon.yml`, `/moon.yml` and `/.moon/*.yml`, so a change to any
project's task definitions moves this task's hash. `moon hash` shows 17
such files among 30 hashed inputs in total.

This needs saying plainly, because
`../../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md`
rules that no task declares another project's files as inputs. The rule is
not being bent here; it does not reach this case:

- adr-0006's defects were coarseness (`project://` walks whole directories,
  build trees included), racing (one task hashing a tree another rewrites)
  and non-transitivity. None applies. These are seventeen named files, no
  directory is walked, no build tree is reachable, and no task writes a
  `moon.yml`.
- adr-0006's fix is to depend on an output-declaring task instead. There is
  no such task to depend on. The project graph is not built by anything; it
  *is* the set of `moon.yml` files. Depending on every project's `build`
  task would be both wrong (the explorer consumes none of their artefacts)
  and useless (it would miss a config-only project that has no build task).
- adr-0006 is about **dependency** edges. The explorer does not depend on
  the other projects. It reports on them. That is a different relationship,
  and it is the reason this project sits in `platform` in its own
  `capabilities.yml` rather than in a capability.

**Both tasks set `cache: false`.** Git history is a real input that moon
cannot hash: it lives in `.git`, and nothing in the working tree moves when
a commit lands. A cached `explorer:generate` would serve change-frequency
data from whenever the cache was filled, and would keep serving it, silently
— the exact failure the site exists to argue against. `explorer:build` is
uncached for the matching reason: it consumes `src/generated/model.json`,
which is gitignored and therefore not hashable as an input under moon's
default `vcs` walk strategy, so a cached build would not notice the model
changing underneath it. The cost is about four seconds, all of it.

**`capabilities.yml` is checked against the graph, and the check fails the
build.** Every project moon reports must appear exactly once, either as a
component of a capability or in a `platform` list with a stated reason.
A new project fails `explorer:generate` until someone says where it
belongs. Verified by adding a probe project mid-stage: the task failed with
`project probe is in no capability and not listed as platform`.

The `platform` list exists so that "capability" keeps meaning something a
business buys. Without it, `config`, `spec` and the explorer itself would
have to be given invented capabilities, or the coverage check would have to
be dropped. Each entry carries a one-line reason, so `platform` cannot
quietly become the drawer everything is swept into.

The file is also capped at sixteen capabilities, enforced by a test.
seed.md §9 says the input is "kept honest by being small (a dozen
capabilities, not hundreds)"; a cap is what turns that sentence into a
property.

## Consequences accepted

- **Nothing is cached, so `moon ci` pays for the explorer on every affected
  run.** Measured at 4.4 seconds cold for `generate` plus `build`.
- **A fresh clone cannot type-check `explorer` without running
  `generate` first.** `src/generated/model.json` is gitignored, and the site
  imports it. `build` and `test` both declare `deps` on `generate`, so every
  entry point through moon is correct; `pnpm run build` on its own in a
  clean tree is not. Same shape as `core-api-client`'s generated schema.
- **The generator runs `moon` inside `moon`.** If a future moon version
  takes an exclusive lock for graph queries, this deadlocks rather than
  degrading. It is one call site, in `src/generate/main.ts`.
- **Co-change is measured only between capability components.** The root
  pseudo-project's source is `.`, so it owns every top-level file and would
  co-change with everything; including it made the strongest "hidden
  coupling" signal in the repository `root + server`, which means nothing.
  The consequence is that a genuine coupling to a platform project is
  invisible to that overlay.
- **Change frequency is a per-project count, not a per-file one.** A project
  that changes constantly in one file reads the same as one that changes
  across its whole surface. `files` is recorded alongside `commits` so the
  distinction is at least available.

## Alternatives considered

**Commit the generated model.** It would make the site buildable from a
clean checkout with no `generate` step, and it would make the model
reviewable in a diff. Rejected: a committed model can be stale, and a stale
model is indistinguishable from a fresh one when you are looking at the
site. The one property seed.md asks for is the one this would give up.

**A `root:project-graph` task producing the JSON as a declared output, with
`explorer:generate` depending on it.** This would satisfy adr-0006's letter.
Rejected: that task would itself have to declare `/*/moon.yml` as inputs, so
the problem moves rather than resolves, and it puts a task that exists only
for the explorer's benefit into the workspace's root project.

**Hashing git history into the task key** — for instance by declaring
`.git/HEAD`. Rejected as a half-measure: it moves on a commit but not on an
amend or a rebase, and it is exactly the kind of clever input declaration
that looks correct and is not.

# ADR-0004: The project graph is more than the `moon.yml` files

**Status:** Accepted. Supersedes adr-0001.
**Date:** 2026-09-07
**Stage:** 10 (review)

## Context

adr-0001 settled how the explorer gets its data: shell out to `moon`,
declare the `moon.yml` files as inputs, cache nothing, and fail the build
when `capabilities.yml` stops matching the graph. Every one of those
decisions still holds and is restated below.

One sentence of its reasoning was **factually wrong**, and it was load
bearing:

> The project graph is not built by anything; it *is* the set of `moon.yml`
> files.

It is not. `.moon/workspace.yml` sets `projects.globs: ["*"]`, so **every
top-level directory is a project**, whether or not it carries a `moon.yml`.
`config/` and `spec/` proved it at the time that ADR was written: both were
in `moon query projects` and neither had a `moon.yml`.

That matters because adr-0001 used the sentence to argue that declaring
`/*/moon.yml` covered the whole input. It does not, and the gap is not
cosmetic. Measured: a bare `a1probe/` directory holding one markdown file
takes `moon query projects` from 17 projects to 18, yet
`explorer:generate`'s hash stays byte-identical at `0534faae`, and
`moon query tasks --affected` for that one file returns `{}`. So under
`moon ci` the site is not regenerated at all, and the fail-closed
capability check — the thing that is supposed to make a new project
impossible to ignore — never runs.

A hand-run `moon run explorer:generate` does catch it, because
`cache: false` forces the task to re-execute. But `cache: false` was decided
for an unrelated reason (git history is not hashable), so the only thing
standing between this hole and a silently wrong site was a decision taken
for another purpose. Two decisions were accidentally covering for each
other, and adr-0001 recorded neither fact.

A second, narrower gap was found in the same review. seed.md §9 asks the
zoomed-in view to link into each component's `spec/` directory, and it does
— from `git ls-files`. Nothing declared those files as inputs, so adding an
ADR or a mock moved no hash and `moon ci` left the site linking the old
spec directory.

## Decision

### The corrections

**The project graph is `.moon/workspace.yml`'s `projects.sources` plus its
`projects.globs` discovery, joined with whatever `moon.yml` each discovered
directory happens to have.** Declaring the `moon.yml` files covers the task
definitions and nothing else. A directory with no `moon.yml` contributes no
declarable input.

**The spec directories are declared as inputs.** `explorer:generate` adds
`/*/spec/**/*` and `/spec/**/*` — the second because the workspace-level
`spec/` is the *root* project's spec directory, `specOf(".")` resolving to
the prefix `spec/`. Verified: adding `core/spec/features/a2probe.feature`
moved the hash from `1ad23cd3` to `c782f977`, and
`moon query tasks --affected` for that file returned
`{'core': ['test'], 'explorer': ['generate']}`. Before the change there
were 30 hashed inputs and not one spec file among them.

**The residual hole is disclosed, not closed.** Closing it means declaring
`/*/**/*`, which is `project://` for the entire workspace — precisely the
coarseness `../../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md`
removed, paid on every build, to catch a directory that is covered anyway
the moment it has a `moon.yml`. So the site reports it instead:
`glob-discovered-projects` in the Blind spots view lists every project with
no `moon.yml` of its own.

`config/` and `spec/` each gained a `moon.yml` in this stage, because
`adr-0003-capabilities-are-a-vocabulary-with-local-claims.md` requires
every project to carry a capability claim and a claim needs a file to live
in. That shrinks the hole to genuinely new directories.

**That finding renders empty on every green build, and that is the honest
reading of it.** A claim lives in a `moon.yml`, and the capability check
refuses a project that claims nothing — so any build that gets as far as
writing a model has already forced every project to have one. The two
mechanisms hold each other up: the check keeps the list empty, and the list
names what the check would have caught. Neither survives `moon ci` never
selecting this task, which is the hole itself. The finding says so in its
own text rather than presenting a zero as reassurance.

### What adr-0001 decided, and still stands

**The generator shells out to `moon`.** It runs `moon project-graph --json`
and `moon task-graph --json` from inside `explorer:generate`, which is
itself a moon task. Nested invocation was the main risk and it works: both
are read-only queries against the project cache. Parsing the `moon.yml`
files directly was rejected — it would re-implement task inheritance,
toolchain aliasing and dependency resolution, and the re-implementation
would be the thing that drifts. That argument is *strengthened* by the
correction above: a direct parser would not see a glob-discovered project
at all.

**Named globs over other projects' source files are declared as `inputs`,
and that does not bend adr-0006.** `explorer:generate` lists `/*/moon.yml`,
`/moon.yml`, `/.moon/*.yml`, `/*/spec/**/*` and `/spec/**/*`. `moon hash`
shows 63 hashed inputs, 17 of them `moon.yml` files and 30 of them spec
files. adr-0006's defects were coarseness, racing and non-transitivity;
none applies, because these are named globs over checked-in source, no
directory is walked, no build tree is reachable, and no task writes a
`moon.yml` or a `spec/` file. adr-0006's fix — depend on an output-declaring
task — has no target here, because nothing *builds* the project graph or
the spec directories.

The one input that **did** have such a target is the e2e capability
coverage, and it now uses it: see the next section.

**Both tasks set `cache: false`.** Git history is a real input moon cannot
hash: it lives in `.git`, and nothing in the working tree moves when a
commit lands. A cached `explorer:generate` would serve change-frequency
data from whenever the cache was filled, and keep serving it silently — the
exact failure the site exists to argue against. `explorer:build` is uncached
for the matching reason: it consumes `src/generated/model.json`, which is
gitignored and therefore not hashable as an input under moon's default
`vcs` walk strategy. The cost is about four seconds, all of it.

**The capability claims are checked against the graph, and the check fails
the build.** Every project moon reports must claim a capability the
vocabulary defines, or tag itself `platform` with a stated reason. Verified
with the probe above: `project a1probe claims no capability — tag it
`capability/<id>` or `platform``. The vocabulary is capped at sixteen
entries, enforced by a test, which is what turns seed.md §9's "a dozen
capabilities, not hundreds" into a property. How the vocabulary and the
claims are split is `adr-0003`.

### `e2e:list` replaces the reach into `e2e`'s tree

The first attempt at reading the e2e capability tags ran Playwright from
inside `explorer:generate` — first through `pnpm --filter e2e exec`, then
through `e2e/node_modules/.bin/playwright` — and declared
`/e2e/tests/**/*` and `/e2e/playwright.config.ts` as inputs. Both forms are
the thing adr-0006 exists to prevent: a cross-project dependency expressed
by reaching into another project's tree instead of by depending on a task
that declares an output.

So `e2e` gained a `list` task that writes the resolved test list to
`build/test-list.json` and **declares it in `outputs`**, and
`explorer:generate` expresses the edge as `deps: ["e2e:list"]`, reading the
file from that declared path.

Measured, the edge is real. `moon hash` on `explorer:generate`:

```json
"deps": { "e2e:list": "fe014070ac013f17295222fd6029e0aec333f77fa1f81cd390da10453c7b794d" }
```

A literal hash, not the `"ignored"` adr-0006 is named for. And it
propagates: editing a comment in `e2e/tests/app-shell.spec.ts` moved
`e2e:list` from `fe014070` to `9c92f73f` and `explorer:generate` from
`5fa479ed` to `75ae13c2`. The two e2e file inputs were dropped; `moon hash`
confirms the only remaining `e2e/` entries are `e2e/moon.yml` and
`e2e/spec/decisions/adr-0001-dockerized-e2e-stack.md`, both reached by the
generic `/*/moon.yml` and `/*/spec/**/*` globs rather than by anything
e2e-specific.

Three things follow, and all three are improvements:

- `explorer:generate` no longer needs the whole pnpm workspace installed,
  and no longer fails when Playwright's config fails to load. Whether the
  suite can be listed is now `e2e`'s problem, reported against `e2e:list`.
- `explorer` knows nothing about how `e2e` installs its dependencies.
- `e2e:list` declares `stack.ts` among its inputs, which
  `explorer:generate` never did, even though `playwright.config.ts` imports
  it. The edge got *more* complete, not less.

## Consequences accepted

- **`explorer` gives up its `layer: tool`.** `e2e` is `layer: automation`,
  and moon's `enforceLayerRelationships` refuses it — verified:
  `Layering violation: Project explorer with layer tool cannot depend on
  project e2e with layer automation`. Leaving the layer `unknown` scopes the
  exemption to this project's own edges instead of relaxing the constraint
  workspace-wide, which is the same device and the same reasoning
  `core-api-client/moon.yml` already carries for its deliberate
  library → application edge. The cost is that the site now reports
  `layer unknown` for itself, and that a genuinely wrong edge out of
  `explorer` would no longer be caught.
- **The constraint was expressing something true.** A reporting tool
  depending on the end-to-end suite is an odd shape, and adr-0001's claim
  that "the explorer does not depend on the other projects, it reports on
  them" is now only three-quarters true: it reports on all of them and
  genuinely consumes one's artefact.
- **`explorer` also sets `syncProjectReferences: false`.** The new
  `dependsOn` made moon's TypeScript toolchain synthesise a project
  reference to `e2e`, whose tsconfig is `noEmit` and not `composite`, so
  `tsc` refused to compile: `Referenced project '.../e2e' must have setting
  "composite": true`. Same setting and same reason as `e2e`'s own edge onto
  `web`. `explorer` imports no TypeScript from `e2e`; it reads a JSON file.
- **An e2e spec edit reaches `explorer:generate` through the dependent walk
  rather than through a matching input.** `moon query tasks --affected` for
  `e2e/tests/app-shell.spec.ts` alone reports `{'e2e': ['list', 'test']}`;
  with `--downstream deep` it reports
  `{'e2e': ['list','test'], 'explorer': ['build','generate','test']}`. That
  walk is `moon ci`'s documented mechanism and seed.md §1's, so this is the
  normal path — but it is a different path from the one the dropped file
  inputs used, and worth knowing when reading an affected query by hand.
- **A new top-level directory with no `moon.yml` is still invisible to this
  task's hash**, as set out above.
- **Nothing is cached, so `moon ci` pays for the explorer on every affected
  run.** Measured at 4.4 seconds cold for `generate` plus `build`.
- **A fresh clone cannot type-check `explorer` without running `generate`
  first.** `src/generated/model.json` is gitignored and the site imports it.
  `build` and `test` both declare `deps` on `generate`, so every entry point
  through moon is correct; `pnpm run build` on its own in a clean tree is
  not. Same shape as `core-api-client`'s generated schema.
- **The generator runs `moon` inside `moon`.** If a future moon version
  takes an exclusive lock for graph queries, this deadlocks rather than
  degrading. It is one call site, in `src/generate/main.ts`.
- **Co-change is measured only between capability components.** The root
  pseudo-project's source is `.`, so it owns every top-level file and would
  co-change with everything; including it made the strongest hidden-coupling
  signal in the repository `root + server`, which means nothing. A genuine
  coupling to a platform project is therefore invisible to that overlay.
- **Change frequency is a per-project count, not a per-file one.** A project
  that changes constantly in one file reads the same as one that changes
  across its whole surface. `files` is recorded alongside `commits` so the
  distinction is at least available.

## Alternatives considered

**Amend adr-0001 in place.** It was wrong about one sentence and the rest
was sound, so correcting the sentence looked proportionate. Rejected by the
project owner, and the rule is right: `../../spec/decisions/README.md` makes
ADRs immutable, and an ADR that was wrong about the mechanism it documents
is worth recording as a decision rather than erasing. A reader who wants to
know why the `moon.yml` inputs are declared the way they are should be able
to find the reasoning that was tried and found wanting.

**Declare `/*/**/*` and close the hole.** Rejected above: it is
`project://` for the whole workspace.

**Give the workspace a `root:project-graph` task emitting the JSON as a
declared output.** This would satisfy adr-0006's letter for the graph
inputs the way `e2e:list` now does for the coverage input. Rejected on the
same ground adr-0001 gave: that task would itself have to declare
`/*/moon.yml` as inputs, so the problem moves rather than resolves, and it
puts a task existing only for the explorer's benefit into the root project.
The distinction from `e2e:list` is that `e2e` had a real reason to be able
to list its own tests; the root project has no reason to dump the graph
except this one.

**Commit the generated model.** It would make the site buildable from a
clean checkout with no `generate` step, and reviewable in a diff. Rejected:
a committed model can be stale, and a stale model is indistinguishable from
a fresh one when you are looking at the site. The one property seed.md asks
for is the one this would give up.

**Hashing git history into the task key**, for instance by declaring
`.git/HEAD`. Rejected as a half-measure: it moves on a commit but not on an
amend or a rebase, and it is exactly the kind of clever input declaration
that looks correct and is not.

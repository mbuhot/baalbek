# ADR-0003: Capabilities are a central vocabulary; the claims on it are local

**Status:** Accepted
**Date:** 2026-09-07
**Stage:** 10

## Context

seed.md §9 makes `capabilities.yml` the explorer's one hand-maintained
input: a "capability → component mapping, kept honest by being small". The
first implementation took that literally — one file holding the capability
name, its description, and the list of components serving it.

Two things are wrong with that shape, and only one of them is about
tidiness.

**Adding a component means editing another project.** A new component
cannot be described without opening a file in `explorer/`. That is the same
cross-project edit seed.md §8 removes for specifications, where a
component's `spec/` lives inside the component precisely so the thing that
describes it moves with it.

**The claim is metadata about the component, and it was stored away from
the component.** Nothing in `billing/` said what `billing` is for. A reader
in that directory had to know the explorer existed to find out.

There is a third gap the single file could not close at all. seed.md §9
asks the zoomed-out view to carry a "where to invest next" signal. Change
frequency and coupling answer *where the work is*. Neither answers *what is
unproven*, and the repository already holds that answer: the e2e suite
knows which journeys exist.

## Decision

**`explorer/capabilities.yml` holds the vocabulary only** — `id`, `name`,
`description`. It is the artefact a CTO reads, and one file is what makes
"a dozen capabilities, not hundreds" checkable at a glance. The
sixteen-entry cap stays, enforced by a test.

**Each project claims its capabilities as project tags in its own
`moon.yml`**, spelled `capability/<id>`:

```yaml
tags:
  - "capability/job-intake"
  - "capability/work-order-scheduling"
```

A project that serves no business capability tags itself `platform`, and
`capabilities.yml` carries its one-line reason. The reason stays central on
purpose: `platform` is an exception register, and the value of a register
is that all of it is on one screen.

**Each e2e spec claims capabilities as Playwright tags**, spelled
`@capability/<id>`:

```ts
test("shows a job created through the API", {
  tag: ["@capability/dispatch-board", "@capability/job-intake"],
}, async ({ page, request }) => { ... });
```

So one vocabulary spans all three of what a capability *is*, which
components *serve* it, and which journeys *prove* it — and a capability's
coverage can be run on demand: `moon run e2e:test -- --grep
@capability/dispatch-board` lists two tests where
`@capability/invoicing` lists none.

`explorer:generate` joins the three and fails closed:

| Condition | Result |
|---|---|
| A project claims a capability the vocabulary does not define | fail |
| A project claims nothing and is not tagged `platform` | fail |
| A project is tagged `platform` and claims a capability | fail |
| A project is tagged `platform` with no reason in `capabilities.yml` | fail |
| `capabilities.yml` names a platform project that is not tagged `platform` | fail |
| A capability no project claims | fail |
| An e2e spec claims a capability the vocabulary does not define | fail |
| An e2e spec claims nothing | fail |
| **A capability no e2e spec claims** | **reported, not failed** |

The last row is deliberately out of step with every row above it. Failing
on missing coverage would buy a hollow spec — someone writes the thinnest
test that satisfies the check, and the signal is destroyed by the act of
enforcing it. Reported, it is exactly the "where to invest next" line
seed.md §9 asks for, and it currently reads `account-access`,
`quote-pricing`, `invoicing`.

## Why the tags are read the way they are

**Project tags come from `moon project-graph --json`**, at
`data.<n>.config.tags`. The generator already parses that document, so
there is no second shell-out and no second parser. `moon query projects
--tags 'capability/*'` answers the same question for a human, and
`tag=capability/job-intake` works in MQL.

The spelling is `capability/<id>`, not `capability-<id>` or
`capability:<id>`. Moon rejects a colon in a tag id — verified:
`Invalid identifier format for capability:work-order`. A slash is legal and
is unambiguous, where a dash leaves no visible boundary between the
namespace and an id that itself contains dashes. Tags that are not
`capability/…` or `platform` are ignored, because moon also uses tags for
task inheritance (`.moon/tasks/tag-<tag>.yml`) and this must not collide
with that.

**e2e tags come from `playwright test --list --reporter=json`, never from
reading the spec files.** Playwright owns that parser: tags can be declared
in the options object, appended to a title, or inherited from an enclosing
`describe`, and a hand-rolled reader that gets one of those wrong reports
confidently and wrongly. That is the same failure the edge classifier was
scrutinised for, and the mitigation is not to write the second
implementation.

Note the JSON reporter emits tags with the leading `@` **stripped**
(`capability/job-intake`, not `@capability/job-intake`), while `--grep`
matches the `@` form. The generator accepts either spelling, so a future
reporter change does not silently produce "no capability has coverage".

**The reporter writes to a file, not to stdout.** The first version piped
`pnpm --filter e2e exec playwright test --list --reporter=json` and parsed
stdout. It worked locally and failed under `moon ci` with
`Unexpected non-whitespace character after JSON at position 165`: pnpm
detects an agent environment and prints its own NDJSON banner line ahead of
the command's output. Anything sharing that stream can do the same. So
`e2e:list` sets `PLAYWRIGHT_JSON_OUTPUT_NAME` and the reporter writes
`build/test-list.json`, which takes every other writer on stdout out of the
picture.

**The listing is `e2e`'s own task, and the edge onto it is a `deps` entry.**
`explorer:generate` does not run Playwright. `e2e:list` does, declares
`build/test-list.json` in `outputs`, and `explorer:generate` names it in
`deps` and reads the declared path — so the edge is hashed through the
outputs mechanism like every other cross-project edge here, and nothing in
`explorer` reaches into `e2e`'s tree. See
`adr-0004-the-project-graph-is-more-than-the-moon-yml-files.md` for the
measurement and for what running Playwright from inside `explorer:generate`
cost.

## Consequences accepted

- **`explorer:generate` depends on `e2e:list`, so `explorer` depends on
  `e2e`.** Retagging a spec moves `e2e:list`'s hash and therefore this
  task's. The cost is a project edge from a reporting tool onto the
  end-to-end suite, and the `layer` and `syncProjectReferences` concessions
  that edge needs; adr-0004 records both.
- **A missing test list fails the build rather than reporting no coverage.**
  Fail-closed by choice: a coverage report that quietly degrades to "nothing
  is covered" is worse than a build error. Whether the suite can be listed
  at all is now `e2e:list`'s problem, and listing resolves specs without
  launching a browser, so no browser binary is needed.
- **Adding an e2e test now requires choosing a capability for it.** That is
  the point, and it is also friction on a test someone wants to write
  quickly.
- **`config/` and `spec/` gained a `moon.yml`.** They had none, and a
  project with no config file cannot carry a tag. This is a side benefit:
  they were the two projects `adr-0001`'s glob-discovery hole was hiding,
  and they no longer are.
- **A capability the vocabulary defines but nobody serves fails the
  build.** So the vocabulary cannot describe an aspiration. A capability
  that is planned rather than built has to wait for the component that
  serves it.
- **The mapping is no longer reviewable in one diff.** Reading which
  components serve a capability now means `moon query projects --tags`, or
  the generated site. The register that stayed central — `platform` — is
  the one where the whole-list view is the point.

## Alternatives considered

**Keep the components list in `capabilities.yml`.** Simplest, and it keeps
the mapping reviewable in one file. Rejected on the cross-project edit: the
file nobody owns is the file that rots, and seed.md §8 already settled this
question for specifications.

**Put the platform reason in the project's `moon.yml` too**, as a
`project.description` or a comment. Rejected: a comment is not checkable,
and spreading five exceptions across five files removes the one property
that stops `platform` becoming a drawer — that you can read all of it at
once.

**Derive coverage by grepping the spec files for `@capability/`.** No
dependency on Playwright's CLI, and faster. Rejected for the reason stated
above: Playwright's tag rules include inheritance from `describe` blocks
and title-suffix tags, and a partial reimplementation under-reports
coverage while looking authoritative.

**Fail the build on a capability with no e2e coverage.** Symmetrical with
every other rule here, and tempting for that reason alone. Rejected: it
converts a diagnostic into a box to tick, and the box gets ticked.

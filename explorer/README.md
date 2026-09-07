# explorer

**Language:** TypeScript

**Purpose:** Static site from project-graph JSON + git stats + `capabilities.yml`.

The self-built architecture explorer (seed.md §9). Regenerated on every
build from moon's own graph, so it cannot drift from the workspace it
describes.

## Running it

```
moon run explorer:build      # generate the model, type-check, bundle into dist/
moon run explorer:test       # the vitest suite (also runs build, so also type-checks)
```

`dist/` is an ES module and needs a static file server; browsers refuse
module scripts over `file://`. Any server will do — the model is bundled
into the page, so nothing else is needed.

## Inputs

| Input | Read by |
|---|---|
| `moon project-graph --json` | `src/generate/moon-graph.ts`, `src/generate/capabilities.ts` |
| `moon task-graph --json` | `src/generate/moon-graph.ts` |
| `git log --name-only` | `src/generate/git-stats.ts` |
| `git ls-files` | `src/generate/build-model.ts` |
| `playwright test --list --reporter=json` | `src/generate/e2e-specs.ts` |
| `capabilities.yml` | `src/generate/capabilities.ts` |

`capabilities.yml` is the only hand-maintained one, and it holds the
**vocabulary only** — id, name, description. Who serves a capability is a
claim each project makes for itself:

```yaml
# billing/moon.yml
tags:
  - "capability/invoicing"
```

```ts
// e2e/tests/dispatch-board.spec.ts
test("shows a job", { tag: ["@capability/dispatch-board"] }, async () => { ... });
```

`explorer:generate` joins the three and fails when a project or a spec
claims a capability the vocabulary does not define, and when a project
claims nothing at all. A capability with no e2e spec is *reported*, not
failed — that is the "where to invest next" signal, not a box to tick.

```bash
moon query projects --tags 'capability/*'                # who serves anything
moon query projects --tags 'capability/invoicing'        # who serves this
moon run e2e:test -- --grep @capability/invoicing        # what proves it
```

Output is `src/generated/model.json`, which is gitignored and bundled into
the site by `explorer:build`.

## Views

- **Capabilities** — the zoomed-out view, with change-frequency, coupling,
  and e2e-coverage overlays.
- **Project graph** — the zoomed-in view, with per-component detail linking
  into each component's `spec/` directory, and the task graph behind it.
- **Blind spots** — what the graph cannot see, derived rather than asserted.

## Decisions

- [adr-0003](spec/decisions/adr-0003-capabilities-are-a-vocabulary-with-local-claims.md) —
  the vocabulary/claims split, the tag spellings, and which rules fail the
  build.
- [adr-0004](spec/decisions/adr-0004-the-project-graph-is-more-than-the-moon-yml-files.md) —
  why other projects' source files are declared inputs, why the e2e edge is a
  `deps` entry instead, why nothing here is cached, and the hole
  `projects.globs: ["*"]` leaves that this cannot close. Supersedes adr-0001.
- [adr-0005](spec/decisions/adr-0005-co-change-needs-a-breadth-filter-to-mean-anything.md) —
  Cytoscape.js, making the declared-build-edges-only limitation visible, and
  how the co-change signal is filtered. Supersedes adr-0002.

Superseded: [adr-0001](spec/decisions/adr-0001-generated-from-the-live-graph.md)
(wrong about what the project graph is made of),
[adr-0002](spec/decisions/adr-0002-blind-spots-are-a-view-not-a-footnote.md)
(co-change counted every pair in every commit).

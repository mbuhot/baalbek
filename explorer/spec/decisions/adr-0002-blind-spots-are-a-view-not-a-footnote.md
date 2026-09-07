# ADR-0002: The blind spots are a view, not a footnote

**Status:** Superseded by [adr-0005](adr-0005-co-change-needs-a-breadth-filter-to-mean-anything.md)
**Date:** 2026-09-07
**Stage:** 10

## Context

seed.md §9 ends on the explorer's known gap: the graph only shows declared
build edges, so runtime HTTP calls, shared tables and copied constants are
invisible. It then says this gap is the pitch. §6 is the answer to it —
convert runtime edges into build edges and the graph becomes true — and §10
makes it the demo's narrative arc.

An architecture site that draws what it knows and says nothing about what it
does not know is worse than no site, because the reader takes the drawing
for the territory. That is the failure mode the client arrived with.

Two design questions follow. What renders the graph, and where does the
honesty live.

## Decision

### Cytoscape.js renders the graph

seed.md offers Cytoscape.js or D3. Cytoscape.js, because the work here is
graph work: layout of a directed acyclic graph, hit-testing on nodes, pan
and zoom, and per-edge styling driven by data. Cytoscape provides all four.
D3 provides the primitives to build them, and the difference is a few
hundred lines of code this project would then own.

Cost accepted: 489 kB of bundle, 153 kB gzipped, nearly all of it
Cytoscape. For an internal reporting site served over a LAN or a CI
artifact host that is not a real cost, and the alternative — hand-rolled
SVG — buys the saving with code that has to be maintained.

The layout is `breadthfirst`, directed, which reads correctly for a
dependency graph: consumers first, dependencies after. The task graph
transposes it so ranks run left to right, because `project:task` labels
collide when stacked in a row and do not when stacked in a column. `dagre`
would rank more tidily and is another dependency; the built-in layout is
good enough at seventeen projects and thirty-one tasks.

### The honesty is derived, and it is one of three views

Three views, matching seed.md's audience split plus one:

- **Capabilities** — zoomed out, for the CTO. Capability cards with change
  frequency and coupling overlays, ranked. Deliberately not derived from
  code structure, so a refactor does not redraw it.
- **Project graph** — zoomed in, for an engineer or an agent. The real
  graph, a per-component detail panel, and links into each component's
  `spec/` directory.
- **Blind spots** — what the graph cannot see.

Every item in the third view is **derived from the same inputs as the other
two**. Nothing there is a hand-written caveat. That matters because a
hand-written caveat is a claim about a past state of the repository, and it
decays exactly like the documentation this project exists to replace. The
six findings are:

| Finding | Derived from |
|---|---|
| Declared edges that cannot invalidate a cache | project edges with no output-declaring task dep behind them |
| Task deps moon records as `ignored` | task edges whose upstream declares no `outputs` |
| Tasks moon does not cache | `cache: false` in the task graph |
| Projects with no tasks | the project graph |
| Projects that change together with no edge between them | git history, cross-checked against the graph |
| Capabilities whose components no build edge connects | `capabilities.yml`, cross-checked against the graph |

The last two are the ones that speak to the seed's actual gap. A pair of
components repeatedly edited in one commit with no declared dependency
between them is the shape a runtime-only edge leaves in history. It is
evidence to follow, not a proven edge, and the view says so.

The last finding is currently empty, and the view states that an empty list
is the result seed.md §6 is after rather than an absence of evidence. In the
"before" state seed.md §10 describes it would be full.

### The limitation is visible in the graph itself, not only in that view

A separate tab is still a place a reader can fail to visit. So:

- A banner sits under the header on every view: *Declared build edges only*,
  linking to the blind-spot view.
- Edge colour in the project graph encodes hashing reach, not decoration.
  Green is a direct task dep on an output-declaring task. Amber dashed
  reaches the dependency only through a third project. Red dotted is
  declared in `moon.yml` and invisible to hashing — the edge orders work but
  cannot invalidate a cache. The legend says this in words.
- The detail panel repeats it per edge, and names the ignored task deps
  verbatim, so `e2e -> server` reads
  `ignored: e2e:test -> server:image`.

That classification is this repository's own recent history made visible.
`../../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md`
replaced `project://` inputs with task deps on output-declaring tasks; the
edges that convention did not reach are exactly the red ones. As generated
at this commit: `e2e -> server` and `e2e -> web` are declared-only, because
`server:image` and `web:image` produce Docker images rather than files and
so declare no `outputs` — which adr-0006 records as accepted. `server ->
pricing` is amber: real, but reaching moon's hashing only through
`pricing_native`. Nobody wrote any of that down for the site. It fell out
of the graph.

## Consequences accepted

- **The site is 489 kB.** Cytoscape is most of it.
- **The site needs to be served.** It is an ES module, which browsers refuse
  to load over `file://`. `dist/` needs any static file server. The model is
  bundled rather than fetched, so it needs nothing else — no API, no
  backend, no network.
- **Spec links are relative** — `../../core/spec/features/...`, resolved from
  `explorer/dist/index.html`. They work when the site is served from within
  a checkout and break when `dist/` is published on its own. Publishing with
  the spec files, or rewriting the links to a forge URL, is a deployment
  decision this stage does not take.
- **Edge colour claims something moon does not print.** The classification
  is computed here from the two graph dumps. It agrees with `moon hash`,
  which prints `ignored` next to a dead dependency, but it is a
  reimplementation of moon's rule and could fall out of step with a future
  moon version. It is covered by unit tests over fixture graphs, which pin
  the rule but not moon's conformance to it.
- **"Blind spots" is a growing list, and that is intended.** Six findings
  today. A convention that stops holding shows up as a longer list rather
  than as a silent regression.

## Alternatives considered

**A single "explorer" view with filters.** Rejected: it collapses seed.md's
audience split. The CTO view exists because capability framing survives
refactors and code structure does not; folding it into the graph view makes
it a graph view with labels.

**Static SVG rendered at build time, no client JavaScript.** Smaller,
faster, and printable. Rejected because the zoomed-in view's value is
interrogation — click a node, read its tasks, follow the edge, open the ADR
— and that is not a picture.

**Detecting runtime edges by scanning source for HTTP calls and shared table
names.** Tempting, and it would make the gap smaller. Rejected for this
stage: a scanner that finds some runtime edges and misses others produces a
graph that looks complete and is not, which is strictly worse than one that
is visibly incomplete. The co-change finding gets at the same question
without pretending to be exhaustive.

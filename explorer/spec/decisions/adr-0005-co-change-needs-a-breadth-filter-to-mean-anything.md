# ADR-0005: Co-change needs a breadth filter to mean anything

**Status:** Accepted. Supersedes adr-0002.
**Date:** 2026-09-07
**Stage:** 10 (review)

## Context

adr-0002 decided what renders the graph (Cytoscape.js) and where the
honesty lives (a derived Blind spots view, plus edge colour and a banner in
the graph itself). Those decisions hold and are restated below.

Its co-change finding did not work. adr-0002 described it as evidence a
reader should follow — "the shape a runtime-only edge leaves in history" —
and the implementation counted every pair of components touched by the same
commit, reporting a pair once it reached three. On this repository's
seventeen-commit history that made **62 of the 66 possible pairs qualify**,
which is not a signal; it is a list of the components that exist.

Three commits were responsible. `a9bcc0f` (the workspace skeleton) and
`e4ea6d0` each touched all twelve capability components, and `7437758` (the
`project://`-to-`deps` conversion) touched eleven. Each handed every pair
the same free +3. A reader looking at that table learns nothing, and worse,
learns it confidently — the same defect adr-0002 itself warns about for a
source-scanning runtime-edge detector.

Two smaller problems came out of the same review. The change-frequency
overlay took its maximum over *all* projects, so `root`'s 14 commits set the
ceiling while every capability component sat between 4 and 7 and every chip
rendered in the same shade. And the task graph's `spacingFactor` of 0.8 was
tight enough that its labels overlapped, which is the problem adr-0002's
transposition was introduced to solve.

## Decision

### Co-change ignores commits too broad to mean anything

A commit touching more than **a third of the coupled components** is
excluded from pairing. It still counts towards change frequency; only the
pairing is dropped. The threshold is computed from the component count
rather than fixed — `max(2, floor(n / 3))`, so 4 at today's 12 components —
and never falls below a pair, so the rule survives the workspace growing.

The floor for reporting a pair came down from three co-changes to two at the
same time, in one shared constant, `MIN_CO_CHANGE_COMMITS` in
`src/model.ts`. Once the workspace-wide commits are gone a repeat is
evidence rather than an artefact, and at three the table showed a single
row. The constant is shared because the same threshold is applied in two
places — the Blind spots finding and the capability view's table — and it
was previously written as a bare `3` in both.

Measured on this repository's history. Unfiltered: 62 pairs qualified.
Filtered, the whole table is

| Pair | Co-changes | Build edge |
|---|---|---|
| `billing + identity` | 3 | none declared |
| `pricing + pricing_native` | 2 | declared |
| `timeline + timeline_facade` | 2 | declared |

— one question genuinely worth asking, and the two facade pairs the graph
already knows about, which is a good sign that the filter keeps real signal
rather than flattening everything. The Blind spots finding, which reports
only undeclared pairs, is down from 18 items to one.

Weighting each pair `1/(n-1)` instead of excluding the commit was
considered. Rejected: it produces fractional values under a column headed
"Commits", and the exclusion is the rule that can be stated in one sentence
in the view, which it now is.

The calibration is honest about being a calibration. A seventeen-commit
history is small, both numbers are the sort that should be revisited once
there is a year of it, and the consequence is recorded below.

### The change-frequency overlay scales against what it draws

`maxCommits` is computed over the components the capability view actually
renders, not over every project in the graph. `root`'s source is `.`, so it
owns every top-level file; including it in the scale is what flattened the
overlay to one shade. This is the same reasoning adr-0002's successor to the
co-change decision applies, and the same reasoning that already kept `root`
out of the pairing.

### Cytoscape.js renders the graph

seed.md offers Cytoscape.js or D3. Cytoscape.js, because the work here is
graph work: layout of a directed acyclic graph, hit-testing on nodes, pan
and zoom, and per-edge styling driven by data. Cytoscape provides all four.
D3 provides the primitives to build them, and the difference is a few
hundred lines of code this project would then own.

Cost accepted: 489 kB of bundle, 154 kB gzipped, nearly all of it
Cytoscape. For an internal reporting site served over a LAN or a CI artifact
host that is not a real cost, and the alternative — hand-rolled SVG — buys
the saving with code that has to be maintained.

The layout is `breadthfirst`, directed, which reads correctly for a
dependency graph: consumers first, dependencies after. The task graph
transposes it so ranks run left to right, because `project:task` labels
collide when stacked in a row and do not when stacked in a column. It also
needs a **wider** `spacingFactor` than the project graph — 1.8 against 1.25
— because its labels sit beside the node rather than under it, so ranks that
fit at project scale overlap at task scale. adr-0002 set 0.8 and the labels
collided, which defeated the transposition. `dagre` would rank more tidily
and is another dependency; the built-in layout is good enough at seventeen
projects and thirty-one tasks.

The heading and lede switch with the mode, too. adr-0002's implementation
left both reading "Project graph" while the task graph was displayed.

### The honesty is derived, and it is one of three views

Three views, matching seed.md's audience split plus one:

- **Capabilities** — zoomed out, for the CTO. Capability cards with change
  frequency, coupling and e2e-coverage, ranked. Deliberately not derived
  from code structure, so a refactor does not redraw it.
- **Project graph** — zoomed in, for an engineer or an agent. The real
  graph, the task graph behind it, a per-component detail panel, and links
  into each component's `spec/` directory.
- **Blind spots** — what the graph cannot see.

Every item in the third view is **derived from the same inputs as the other
two**. Nothing there is a hand-written caveat, because a hand-written caveat
is a claim about a past state of the repository and it decays exactly like
the documentation this project exists to replace. The eight findings are:

| Finding | Derived from |
|---|---|
| Declared edges that cannot invalidate a cache | project edges with no output-declaring task dep behind them |
| Task deps moon records as `ignored` | task edges whose upstream declares no `outputs` |
| Tasks moon does not cache | `cache: false` in the task graph |
| Projects with no tasks | the project graph |
| Projects moon discovered from a directory, not a `moon.yml` | the project graph, cross-checked against the filesystem |
| Capabilities no e2e spec claims | `e2e:list`'s test list, cross-checked against the vocabulary |
| Projects that change together with no edge between them | git history, filtered as above, cross-checked against the graph |
| Capabilities whose components no build edge connects | the capability claims, cross-checked against the graph |

adr-0002 had six. The two additions come from the same review: the fifth
from `adr-0004-the-project-graph-is-more-than-the-moon-yml-files.md`, and
the sixth from `adr-0003-capabilities-are-a-vocabulary-with-local-claims.md`.

The last two are the ones that speak to seed.md's actual gap. A pair of
components repeatedly edited in one commit with no declared dependency
between them is the shape a runtime-only edge leaves in history. It is
evidence to follow, not a proven edge, and the view says so.

The last finding is currently empty, and the view states that an empty list
is the result seed.md §6 is after rather than an absence of evidence. In the
"before" state seed.md §10 describes it would be full.

The fifth is this view reporting a hole in the generator that feeds it. That
is the premise working: the limitation is derived, so it did not have to be
remembered. It renders empty on every green build, for the reason adr-0004
records and the finding's own text repeats; it is the one finding whose
value is entirely in its explanation, and it stays a derived list rather
than a paragraph so that a project slipping into that state would appear in
it.

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
  verbatim, so `e2e -> server` reads `ignored: e2e:test -> server:image`.

That classification is this repository's own recent history made visible.
`../../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md`
replaced `project://` inputs with task deps on output-declaring tasks; the
edges that convention did not reach are exactly the red ones. As generated
at this commit: `e2e -> server` and `e2e -> web` are declared-only, because
`server:image` and `web:image` produce Docker images rather than files and
so declare no `outputs` — which adr-0006 records as accepted.
`server -> pricing` is amber: real, but reaching moon's hashing only through
`pricing_native`. Nobody wrote any of that down for the site. It fell out of
the graph.

## Consequences accepted

- **The co-change overlay is calibrated, not raw.** Two numbers stand
  between the git history and what the view says: the breadth cut and the
  reporting floor. Both are stated here, both are in one place in the code,
  and the view states the breadth rule in the caption — but a reader is
  looking at a filtered signal, not at the history.
- **A genuinely workspace-wide coupling is now invisible.** If two
  components really do change together only in commits that also touch
  everything else, this overlay will not say so. That is the price of the
  filter, and it is the right way round: a false negative in a
  "question worth asking" panel costs less than 62 false positives.
- **The change-frequency overlay is honest but flat.** Scaling against the
  drawn components moves the chips from all `heat-2` to buckets 3 and 4 —
  better, but the underlying spread really is only 4 to 7 commits on a young
  repository. The overlay will get more informative with history, not with
  more code.
- **The site is 489 kB.** Cytoscape is most of it.
- **The site needs to be served.** It is an ES module, which browsers refuse
  to load over `file://`. `dist/` needs any static file server. The model is
  bundled rather than fetched, so it needs nothing else — no API, no
  backend, no network. Three comments in the source claimed the opposite
  ("opens without a server") and were corrected in this review; adr-0002 and
  the README always had it right.
- **Spec links are relative** — `../../core/spec/features/...`, resolved
  from `explorer/dist/index.html`. They work when the site is served from
  within a checkout and break when `dist/` is published on its own.
  Publishing with the spec files, or rewriting the links to a forge URL, is
  a deployment decision this stage does not take.
- **Edge colour claims something moon does not print.** The classification
  is computed here from the two graph dumps. It agrees with `moon hash`,
  which prints `ignored` next to a dead dependency, but it is a
  reimplementation of moon's rule and could fall out of step with a future
  moon version. It is covered by unit tests over fixture graphs, which pin
  the rule but not moon's conformance to it.
- **"Blind spots" is a growing list, and that is intended.** Eight findings
  today, up from six. A convention that stops holding shows up as a longer
  list rather than as a silent regression.

## Alternatives considered

**Amend adr-0002 in place.** The co-change rationale is an addition rather
than a contradiction, so appending it looked harmless. Rejected by the
project owner: growing a findings table from six to eight and adding a
calibration section is mutation of a record, and `../../spec/decisions/README.md`
makes ADRs immutable. The mechanism the old ADR described — count every
pair, report at three — was genuinely wrong, and recording that is worth
more than a tidy document.

**Weight each pair `1/(n-1)` rather than excluding broad commits.**
Rejected above: fractional counts under a "Commits" column, and no sentence
the view can state.

**Raise the reporting floor instead of filtering breadth.** Rejected by
measurement: the three broad commits give every pair +3, so any floor at or
below 3 admits all 66 pairs and any floor above it discards the real ones
along with the noise. The problem is the input, not the threshold.

**A single "explorer" view with filters.** Rejected: it collapses seed.md's
audience split. The CTO view exists because capability framing survives
refactors and code structure does not; folding it into the graph view makes
it a graph view with labels.

**Static SVG rendered at build time, no client JavaScript.** Smaller,
faster, and printable. Rejected because the zoomed-in view's value is
interrogation — click a node, read its tasks, follow the edge, open the ADR
— and that is not a picture.

**Detecting runtime edges by scanning source for HTTP calls and shared
table names.** Tempting, and it would make the gap smaller. Rejected for
this stage: a scanner that finds some runtime edges and misses others
produces a graph that looks complete and is not, which is strictly worse
than one that is visibly incomplete. The co-change finding gets at the same
question without pretending to be exhaustive — provided it is filtered,
which is what this ADR is for.

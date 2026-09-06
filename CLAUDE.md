# CLAUDE.md

Guidance for coding agents working in this repository.

## What this repo is

`baalbek` is Alembic's consolidation-demo reference project — see `seed.md` for the full spec
(a decision record) and `PLAN.md` for the concrete stage-by-stage build plan and session
decisions. Both are the source of truth; this file covers conventions PLAN.md/seed.md don't.

## Documentation & comments

Write all comments and docs in ASD-STE100 style: short sentences, active voice, one idea per
sentence. A comment longer than the code it describes is a defect.

- A moduledoc (or file-level header comment, for non-Elixir files) describes the abstraction the
  module/file provides — what a user of it needs to know, never internal implementation details.
- A moduledoc/file header is **one sentence**. Only something presenting a genuinely complex
  abstraction adds a blank line and a paragraph of at most three short sentences. Document
  internal complexity next to the code it concerns, never in the header.
- A config file's or task's comment is one line. A private-function comment is one sentence.
- Rationale, tradeoffs, alternatives considered, and the history of a decision live in commit
  messages and ADRs (`spec/decisions/`) — never in code comments. A comment
  states only a constraint the code cannot show, in one line, naming the specific value or case.
- Never describe what the code used to do, unless it carries a real compatibility affordance for it.
- Don't commit intermediate or superseded planning/scratch artefacts — drop iteration debris
  before a stage is committed.

## Specification directories

A component's `spec/` directory holds its specification (seed.md §8), and only what it genuinely
has: `features/` (Gherkin acceptance criteria, executed by ExUnit), `mocks/` (dated UI mock
snapshots), `decisions/` (ADRs). Never create an empty one to complete the pattern.

- ADR conventions — numbering, the immutability rule, where a cross-component decision goes —
  live in `spec/decisions/README.md`. An ADR is the one place longer rationale prose is correct.
- ADRs record architectural decisions, not process ones. How the work is specified and reviewed
  belongs in this file.
- Gherkin features are executable. A `.feature` file with no wired steps is a defect, not a
  placeholder.

## Reviewing

A review checks the work against the spec, not only against the brief that produced it. A brief is
its own artefact and can be wrong: it can under-apply a principle, or apply one to a component and
silently drop it for the neighbouring one. Read `seed.md` and `PLAN.md` and say when the brief
itself is the defect.

This is not hypothetical. Stage 9 required the server tier to run its real release artifact, then
let the web tier be served by a config that existed only in the test directory — because the brief
listed that as acceptable, so the implementation conformed and the review passed it.

## Test tree layout (Elixir)

`test/` mirrors `lib/`: `test/a/b_test.exs` covers `lib/a/b.ex`, `test/a/` covers `lib/a/`.
`test-paths.py` owns that mapping — `--check` enforces it as the `root:test` Moon task, and
`--select` backs each app's `mix test.changed`. Move tests when you move code.

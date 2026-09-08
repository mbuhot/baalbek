# CLAUDE.md

Guidance for coding agents working in this repository.

## What this repo is

`baalbek` is Alembic's consolidation-demo reference project: fifteen components in five
languages, in one Moon workspace, with the dependency graph the build tool sees made to match the
one the system actually has. Each component's `spec/` states what that component must do, and
`spec/decisions/` records why it is built the way it is. Those are the source of truth; this file
covers the conventions they do not.

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

A component's `spec/` directory holds its specification, and only what it genuinely
has: `features/` (Gherkin acceptance criteria, executed by ExUnit), `mocks/` (dated UI mock
snapshots), `decisions/` (ADRs). Never create an empty one to complete the pattern.

- ADR conventions — numbering, the immutability rule, where a cross-component decision goes —
  live in `spec/decisions/README.md`. An ADR is the one place longer rationale prose is correct.
- ADRs record architectural decisions, not process ones. How the work is specified and reviewed
  belongs in this file.
- Gherkin features are executable. A `.feature` file with no wired steps is a defect, not a
  placeholder.

## Case-insensitive hosts

On macOS and Windows the working tree is case-insensitive, so use each path's canonical spelling
exactly and never delete an apparent case-duplicate — both spellings are the one file.

## Build directories are not on the working tree

Everything the build writes lives on local storage, off the bind mount that carries the
source: Moon needs a task's outputs inside its project, so the paths stay put and the storage
moves under them. The devcontainer mounts a named volume over each one; anywhere else, run
`scripts/mount-build-dirs.sh setup`, which bind-mounts them and does not survive a reboot.
`check` says whether they are in place, and `root:test` fails when the devcontainer's
hand-written volume list stops matching the derived one. Each one is a mount point, so
`rm -rf <project>/build` fails with EBUSY; empty the contents instead.

## Reviewing

A review checks the work against the spec, not only against the brief that produced it. A brief is
its own artefact and can be wrong: it can under-apply a principle, or apply one to a component and
silently drop it for the neighbouring one. Read the component's `spec/` and the ADRs its change
touches, and say when the brief itself is the defect.

This is not hypothetical. One change required the server tier to run its real release artifact,
then let the web tier be served by a config that existed only in the test directory — because the
brief listed that as acceptable, so the implementation conformed and the review passed it.

Answer two questions in every review, before anything else.

**What is measurably different now?** Name the observable change. If a measurement shows no
difference, that is a finding, not a footnote. A plugin was built to infer the Elixir dependency
graph. Its review measured that affected-task queries were byte-identical with inference on and
off, reported it as "honest scoping", and passed. The measurement was the disproof.

**Does the outcome do what it was built to do?** State the goal in one sentence and answer against
it. That plugin existed so the Mix dependency graph would not be duplicated by hand in YAML.
Afterwards it was still duplicated by hand, as task `deps`, and nobody re-read the goal against
the result.

A brief may state facts and constraints. It may not state verdicts. "`dependsOn` does not
invalidate" is a fact to verify. "Therefore this stage is a maintenance win and that is fine" is a
conclusion the review exists to reach. Treat a verdict in a brief as the first thing to attack.

An ADR is where a decision's reasoning lives, and `spec/decisions/README.md` has the conventions.
Cite one when it answers a question the code cannot; cite nothing else.

## Test tree layout (Elixir)

`test/` mirrors `lib/`: `test/a/b_test.exs` covers `lib/a/b.ex`, `test/a/` covers `lib/a/`.
Nothing enforces it, so move tests when you move code. Locally, `mix test --stale` reruns
what your change actually affects.

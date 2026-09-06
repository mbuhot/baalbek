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
  messages and ADRs (`spec/decisions/`, once Stage 8 lands) — never in code comments. A comment
  states only a constraint the code cannot show, in one line, naming the specific value or case.
- Never describe what the code used to do, unless it carries a real compatibility affordance for it.
- Don't commit intermediate or superseded planning/scratch artefacts — drop iteration debris
  before a stage is committed.

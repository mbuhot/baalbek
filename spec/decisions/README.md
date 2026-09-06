# Architecture decision records

Every component carries a `spec/` directory (seed.md §8). This one belongs to
the workspace itself, and holds the decisions that cut across components; a
decision confined to one component lives in that component's own
`spec/decisions/`.

## Convention

- One file per decision, named `adr-NNNN-slug.md`, numbered from 0001 within
  each `spec/decisions/` directory independently.
- Every ADR opens with **Status**, **Date**, and the stage it was taken in.
- ADRs are **immutable**. A decision that no longer holds is superseded by a
  new ADR that says so, and the old one is marked `Superseded by adr-NNNN`.
  Neither the reasoning nor the date is edited after the fact.
- An ADR records *why*, not *what*. The code shows what. Capture the
  alternatives that were rejected and the consequences accepted, because
  those are the parts a reader cannot recover from the code.

## Where the other spec directories are

| Directory | Holds |
|---|---|
| `spec/decisions/` (here) | Workspace-wide decisions |
| `core`, `identity`, `billing`, `server` `/spec/features/` | Gherkin acceptance criteria, executed by ExUnit |
| `timeline_facade/spec/decisions/` | The Gleam ↔ Elixir interop decision |
| `web/spec/mocks/`, `web/spec/decisions/` | Dated UI mock snapshots, and the PWA's own decisions |

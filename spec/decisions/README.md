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

## Index

| ADR | Decision | Status |
|---|---|---|
| [0001](adr-0001-ash-boundary-for-ash-domains.md) | `ash_boundary` derives the boundary from the Ash domain | Accepted |
| [0002](adr-0002-cross-language-edges-need-project-inputs.md) | A cross-language edge needs a `project://` input | Superseded by 0006 |
| [0003](adr-0003-pnpm-workspace-without-a-root-package-json.md) | The pnpm workspace has no root `package.json` | Accepted |
| [0004](adr-0004-gherkin-acceptance-specs-run-on-cucumber.md) | Gherkin acceptance specs run on `cucumber` | Accepted |
| [0005](adr-0005-within-app-test-selection-by-path.md) | Within-app test selection is by path convention | Accepted |
| [0006](adr-0006-task-deps-on-output-declaring-tasks.md) | Cross-project edges are task deps on output-declaring tasks | Accepted |
| [0007](adr-0007-ci-runs-moon-ci-inside-the-sandbox-image.md) | CI runs `moon ci` inside the sandbox image, from the runner | Accepted |

## Where the other spec directories are

| Directory | Holds |
|---|---|
| `spec/decisions/` (here) | Workspace-wide decisions |
| `core`, `identity`, `billing`, `server` `/spec/features/` | Gherkin acceptance criteria, executed by ExUnit |
| `server/spec/decisions/` | Release assembly, and how Gleam code reaches the release |
| `timeline_facade/spec/decisions/` | The Gleam ↔ Elixir interop decision (superseded) |
| `web/spec/mocks/`, `web/spec/decisions/` | Dated UI mock snapshots, and the PWA's own decisions |
| `e2e/spec/decisions/` | How the dockerized e2e stack is composed and bootstrapped |
| `moon-elixir-plugin/spec/decisions/` | How `dependsOn` between Elixir projects is inferred from `mix.exs`, and what that does not cover |
| `explorer/spec/decisions/` | How the architecture explorer is generated, how it shows its own blind spots, and how capabilities are claimed. 0001 and 0002 are superseded by 0004 and 0005 |

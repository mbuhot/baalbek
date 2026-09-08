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
- A decision that still holds but whose detail a later ADR changes is marked
  `Amended by adr-NNNN`, naming in one sentence which part moved. The two
  markers are the only permitted edits to a published ADR.
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
| [0005](adr-0005-within-app-test-selection-by-path.md) | Within-app test selection is by path convention | Superseded by 0012 |
| [0006](adr-0006-task-deps-on-output-declaring-tasks.md) | Cross-project edges are task deps on output-declaring tasks | Accepted. Amended by 0010 |
| [0007](adr-0007-ci-runs-moon-ci-inside-the-sandbox-image.md) | CI runs `moon ci` inside the sandbox image, from the runner | Accepted |
| [0008](adr-0008-the-sandbox-image-is-published-to-ghcr.md) | The sandbox image is published to GHCR, and one builder writes the cache | Accepted |
| [0009](adr-0009-where-ci-runs-moon-ci.md) | Where CI runs `moon ci`, and what it may replay | Accepted |
| [0010](adr-0010-third-party-deps-compile-in-their-own-task.md) | Third-party dependencies compile in their own task | Accepted |
| [0011](adr-0011-what-ci-treats-as-affected.md) | CI runs a changed project's consumers, not just the project | Accepted |
| [0012](adr-0012-within-app-test-selection-is-mix-test-stale.md) | Within-app test selection is `mix test --stale` | Accepted. Supersedes 0005 |
| [0013](adr-0013-build-output-lives-off-the-working-tree.md) | Build output lives off the working tree, by moving the storage under it | Accepted |
| [0014](adr-0014-cargo-tasks-serialise-on-the-target-directory.md) | Every cargo task serialises on the shared target directory | Accepted |

## Where the other spec directories are

| Directory | Holds |
|---|---|
| `spec/decisions/` (here) | Workspace-wide decisions |
| `core`, `identity`, `billing`, `server` `/spec/features/` | Gherkin acceptance criteria, executed by ExUnit |
| `server/spec/decisions/` | Release assembly, and how Gleam code reaches the release |
| `timeline_facade/spec/decisions/` | The Gleam ↔ Elixir interop decision (superseded), and the withdrawal of its boundary check |
| `web/spec/mocks/`, `web/spec/decisions/` | Dated UI mock snapshots, and the PWA's own decisions |
| `e2e/spec/decisions/` | How the dockerized e2e stack is composed and bootstrapped |
| `moon-elixir-plugin/spec/decisions/` | How `dependsOn` and the third-party dependency list are read out of `mix.exs` and `mix.lock`, what that does not cover, and what the committed WASM artifact's gate asserts |
| `explorer/spec/decisions/` | How the architecture explorer is generated, how it shows its own blind spots, and how capabilities are claimed. 0001 and 0002 are superseded by 0004 and 0005 |

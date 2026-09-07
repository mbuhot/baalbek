# ADR-0005: Within-app test selection is a path convention, checked by a Moon task

**Status:** Superseded by adr-0012
**Date:** 2026-09-06
**Stage:** 8

## Context

Moon's affected-detection is project-level (seed.md §1): a one-line change to
`billing` reruns `billing`'s whole suite. seed.md §7.3 asks for one level
finer inside an Elixir app — mirror the boundary structure in the test tree
so `lib/billing` maps to `test/billing`, and derive selection from paths.

The mechanism that would seem natural, `boundary`, cannot do this.
`boundary` hooks the compiler tracer, and ExUnit files are scripts evaluated
at runtime — they never pass through the tracer, so `boundary` cannot see the
test tree at all (seed.md §3's accepted limitation). Nothing in the toolchain
knows which tests cover which area.

## Decision

The path convention carries the mapping, and one script owns both halves of
it so they cannot disagree:

- `test-paths.py --select --app <id>` backs a `mix test.changed` alias in
  each Elixir app's `mix.exs`. It diffs against a base ref (default `main`)
  and prints the test paths mirroring what changed.
- `test-paths.py --check` runs as the `root:test` Moon task, and fails when a
  test file sits at a path that mirrors nothing under `lib/`.

The mapping, for a changed `lib/<rel>.ex`: `test/<rel>_test.exs` if that file
exists, otherwise the nearest existing ancestor of `test/<dirname(rel)>` that
holds tests. A changed file that is not under `lib/` — `mix.exs`, `config/`,
`spec/`, test support — selects the whole suite, since any of them can change
every test's outcome.

## Why a convention and not tags

seed.md §7.3 says "no tag bookkeeping", and the reason is worth restating:
a tag is a second description of where a test belongs, maintained by hand
against the first one (the file path), with nothing checking that the two
agree. A convention has only one description. Its correctness is a property
of the directory tree, which a twenty-line script can verify on every build.

## What the check enforces, and what it deliberately does not

**Enforced:** every `test/**/*_test.exs` must mirror either a `lib/` module
(`test/a/b_test.exs` → `lib/a/b.ex`) or a `lib/` directory (`test/a/` →
`lib/a/`). This is the rule that catches real drift: rename `lib/billing/
invoicing` without moving `test/billing/invoicing` and the mapping starts
resolving to a directory that no longer means anything.

**Reported, not enforced:** source files with no mirrored test path, which
therefore select the whole suite. `server` has ten of them —
`lib/server/api/*` is exercised through HTTP by tests that live in
`test/server_web/`, because that is where the code under test actually runs.
Moving those tests to `test/server/api/` would make a change to
`lib/server_web/router.ex` miss them entirely. Falling back to the whole
suite is coarse but sound; a mirrored-but-wrong path is neither. A rule
demanding a mirrored test directory for every source directory would force
exactly that bad trade, so there is no such rule.

## Consequences accepted

- **Selection is a heuristic, not a proof of coverage.** `test/core/
  customer_test.exs` is selected for `lib/core/customer.ex`, but
  `test/core/domain_test.exs` also exercises customers and is not. This is
  the pre-merge gate seed.md §7.4 describes, never the final word: Moon's
  project-level affected-detection and the full suite on main are the
  backstop.
- **Acceptance specs run regardless.** `mix test.changed` still evaluates
  `test_helper.exs`, which compiles the Gherkin features (adr-0004).
- **A Python script sits between Mix and the test run.** The alias shells out
  rather than reimplementing the mapping in each `mix.exs`, so the convention
  check and the selection cannot drift. The cost is a `python3` dependency in
  a Mix alias, which the repo already takes for `check-deps-drift.py`.

## Alternatives considered

**Reimplement the mapping in each app's `mix.exs`.** Rejected: six copies of
the rule, and the Moon check would be a seventh — the drift this ADR exists
to prevent.

**`mix test --stale`.** Mix's own change tracking, which reruns tests whose
compile-time dependencies changed. It is genuinely finer than a path
convention, but it is scoped to one machine's `_build` manifest, not to a
diff against a base ref, so it cannot answer "what should this branch run
before merging" — and it says nothing about whether the test tree still
mirrors the boundary structure, which is the property seed.md §7.3 wants
kept honest.

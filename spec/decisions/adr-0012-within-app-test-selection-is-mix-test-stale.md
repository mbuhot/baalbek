# ADR-0012: Within-app test selection is `mix test --stale`

**Status:** Accepted. Supersedes 0005
**Date:** 2026-09-07
**Stage:** post-Stage 12, during the moon.yml simplification pass

## Context

ADR-0005 built within-app selection out of a path convention: `test-paths.py
--select` diffed against a base ref and printed the mirroring test paths for
a `mix test.changed` alias in each of the four Elixir apps, and
`test-paths.py --check` ran as the `root:test` Moon task to fail when a test
file mirrored nothing under `lib/`.

ADR-0005 considered `mix test --stale` and rejected it on two grounds: it
reads one machine's `_build` manifest rather than a diff against a base ref,
and it says nothing about whether the test tree still mirrors the boundary
structure.

## Decision

`mix test --stale` is the within-app selection mechanism. `test-paths.py`,
the four `mix test.changed` aliases with the `cli/0` and `aliases/0`
functions that existed only to carry them, and the `root:test` task are
deleted. The mirroring convention stays as a convention, documented in
CLAUDE.md and enforced by nobody.

## Why the earlier objections do not hold

**"Not a diff against a base ref."** True, and it does not matter, because
nothing needs a base ref at this layer. Selection against a base ref is what
CI does, one level up: `moon ci` computes affected projects from
`MOON_BASE`..`MOON_HEAD` and runs each affected project's whole suite
(adr-0009, adr-0011). Within-app selection was only ever a local-iteration
convenience — ADR-0005 says so itself, calling it "a pre-merge gate, not a
proof of coverage". For that job the `_build` manifest is the better input:
it is the machine's own record of what this working tree has compiled.

**"Says nothing about the mirroring."** Also true. The check was a
*separate* control that happened to share a script, and it is being dropped
on its own merits: it enforced that every test file mirrors something under
`lib/`, which is a rule about where files sit, not about whether the suite
proves anything. `server` already had ten source files with no mirrored test
path, reported and deliberately not enforced, because `lib/server/api/*` is
tested through HTTP from `test/server_web/`. A rule with a standing
exemption list that large is describing the convention, not enforcing it.

## Why `--stale` is the more accurate answer

The path convention selected `test/core/customer_test.exs` for a change to
`lib/core/customer.ex` and nothing else, and ADR-0005 accepted the
consequence that `test/core/domain_test.exs` also exercises customers and
would not run. `--stale` follows Elixir's compile-time dependency graph, so
it selects that file too. It is finer where the convention was coarse, and
it needs no second description of where a test belongs.

## Deviation from seed.md §7.3

seed.md §7.3 asks for a mirrored test tree with "selection derived from
paths (Mix alias driven by git diff). Convention-checkable; no tag
bookkeeping." This decision keeps the mirrored tree and the absence of tag
bookkeeping, and drops the other two: selection is not path-derived, and
nothing checks the convention. The clause's stated goal — one description of
where a test belongs, no hand-maintained second one — is met by having no
mapping to maintain at all.

## Consequences accepted

- **Nothing detects a test file that mirrors nothing.** Rename a `lib/`
  directory without moving its tests and no task complains. Review is the
  control, as it is for the boundary check `timeline_facade`'s adr-0002
  withdrew on the same reasoning.
- **Selection is per-machine and needs a warm `_build`.** On a cold tree
  `--stale` runs everything, which is correct but not fast.
- **A stale-selected run is still not a proof of coverage.** `moon ci` and
  the full suite on main remain the backstop, unchanged.
- **Python leaves the repository.** `test-paths.py` was one of its two
  Python files and the only one Mix shelled out to.

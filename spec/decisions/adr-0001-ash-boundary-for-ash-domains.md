# ADR-0001: `ash_boundary` derives the boundary from the Ash domain

**Status:** Accepted
**Date:** 2026-09-06
**Stage:** 2 (retrofitted in the `core` fast-follow), applied to 3 onward

## Context

seed.md §3 requires Sasa Jurić's `boundary` in every Elixir app from day one.
The library's normal shape is a hand-written `use Boundary, deps: [...],
exports: [...]` on a module that then names its public surface by hand.

For an Ash app, that surface is already declared. `Core`'s `resources` block
lists every resource, and each `define` in it publishes a code-interface
function. A hand-written `exports:` list next to it is the same information
written twice, and the two drift the moment a resource gains or loses a
`define` — silently, because `boundary` cannot tell that the list was meant
to track the domain.

## Decision

Ash-domain apps (`core`, `identity`, `billing`) use
[`ash_boundary`](https://github.com/mbuhot/ash_boundary), a Spark DSL
extension on `Ash.Domain` that derives the `boundary` declaration from the
domain DSL: `exports` becomes the domain module plus every resource carrying
at least one domain-level `define`. The `boundary` compiler still performs
the enforcement; only the declaration is derived.

Apps with no Ash domain — `pricing_native`, `timeline_facade`, `server` —
keep a hand-written `use Boundary`, because there is nothing to derive from.

## Consequences accepted

- **`ash_boundary` is not on Hex.** It is pinned to a commit sha rather than
  a branch, so the dependency is as reproducible as a version pin, but it is
  a dependency on an unreleased library and there is no upgrade path but to
  move the sha.
- **The rename it forced.** Ash's own convention puts the domain at the app's
  root module (`Core`), while this repo originally had `Core.Domain` with
  `Core` as a plain boundary root. `ash_boundary` derives the boundary *from*
  the domain module, so the domain has to be the boundary root — `Core.Domain`
  became `Core`, and every reference moved with it. Worth knowing before
  wondering why `core` names its domain differently from how a hand-rolled
  boundary would.
- **Compiler ordering is load-bearing and silent when wrong.** `compilers:
  [:boundary] ++ Mix.compilers()`, never appended after. `boundary` registers
  its check via `Mix.Task.Compiler.after_compiler(:app, ...)`, and that
  registration only fires for compiler passes that run after `:boundary`
  itself. Appended last, `:app` has already finished, so the check never runs
  and every violation passes. This was found by a deliberate violating call
  that `boundary` did not flag; the ordering is now identical in all six
  Elixir apps.

## Alternatives considered

**Hand-written `use Boundary` everywhere.** Rejected on the duplication
above. It remains the right answer for apps with no Ash domain, and they
still use it.

**No in-app boundaries, relying on the Postgres role isolation (§5) alone.**
Rejected: role isolation stops one component reading another's *data*, not
one module reaching into another's *internals*, which is the coupling that
makes a later split expensive.

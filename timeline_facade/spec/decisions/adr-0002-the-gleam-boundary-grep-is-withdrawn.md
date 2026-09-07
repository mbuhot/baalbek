# ADR-0002: The grep-based `:timeline` boundary check is withdrawn

**Status:** Accepted
**Date:** 2026-09-07
**Stage:** post-Stage 12, during the moon.yml simplification pass

**Context:** ADR-0001 found that `boundary` cannot police the `:timeline`
edge, because it only ever classifies modules whose names begin `Elixir.`
and Gleam's modules are bare atoms.
`server/spec/decisions/adr-0001-release-assembly-and-gleam-packaging.md`
re-confirmed that cause and recorded the control that stood in its place: a
grep over this app's `lib/**/*.ex` for `:timeline.` outside
`lib/timeline_facade/gleam.ex`, run as `timeline_facade:boundary-check` and
depended on by `timeline_facade:test`.

## Decision

The check is withdrawn. `timeline_facade/scripts/boundary-check.sh`, the
`boundary-check` task, and the `~:boundary-check` dep on `test` are deleted.
`boundary` keeps enforcing the calls it can classify, which is every
Elixir-to-Elixir call in this app.

## Why

The control cost a task in the graph, a script, an input glob, a test
dependency and a line in the README, and it asserted a one-file convention
inside a library whose entire stated purpose is to be that one file. A
reviewer reading a diff that adds `:timeline.` to a second module of
`timeline_facade` does not need a grep to see it.

It was also a weak control for its price. It matches a literal `:timeline.`
prefix in a `.ex` file under `lib/`, so it never saw `apply(:timeline, fun,
args)`, an atom reached through a variable or module attribute, a call from
`test/`, or a call from any of the other five Elixir apps — and the edge it
guards is one those apps could take just as easily.

## Alternatives rejected

- **Widen it** to `apply/3` and the other apps. That buys a more thorough
  grep, not an enforced boundary, and it grows the same cost across six
  projects.
- **Give Gleam real `Elixir.`-prefixed module names**, so `boundary` can
  classify them. ADR-0001 costed this: it means generating an Elixir
  wrapper module per Gleam module, or patching `boundary`. Still true, still
  not worth it.

## Consequence accepted

A direct `:timeline.` call from another module of `timeline_facade`, or from
another app, now compiles and tests green. Nothing detects it
automatically; code review is the only control.

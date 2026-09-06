# ADR-0002: A cross-language edge needs a `project://` input, not just `dependsOn`

**Status:** Accepted
**Date:** 2026-09-06
**Stage:** 4 (discovered), applied in 5 and 6

## Context

seed.md §1 puts the whole correctness argument for caching and
affected-detection on declared inputs, and §3 requires that a Rust change
invalidate the Elixir suites that sit above it. The obvious way to express
that in Moon is the project-level `dependsOn` the plan already calls for:
`pricing_native` depends on `pricing`, `timeline_facade` on `timeline`.

That is not what `dependsOn` does.

## Decision

Every cross-language edge is declared **twice**, for two different reasons:

- `dependsOn` (project level) and `deps` (task level) give **ordering**: the
  crate builds before the facade's tests run.
- A `project://<id>` entry in the consuming task's `inputs` gives
  **invalidation**: it folds the referenced project's file contents into this
  task's hash.

Both are present on `pricing_native:test`, `timeline_facade:test`,
`core-api-client:build`, `web:test`, `web:build`, and `server:test`.

A `project://` on a facade covers the facade's own files, not the foreign
source behind it. `server:test` therefore names `pricing` and `timeline`
directly as well as `pricing_native` and `timeline_facade`: the crate lives
outside `pricing_native/`, and the Gleam package outside `timeline_facade/`.

## Why

A task dependency contributes to the dependent's hash through its declared
`outputs`. `pricing:test` declares none — it runs `cargo test` and produces
no artefact anyone consumes — so Moon treats it as having nothing to hash,
and `pricing_native:test`'s hash did not change when `pricing`'s source did.
This was observed directly during Stage 4: editing the crate left
`pricing_native:test` on a cache hit, replaying a stale pass. Adding
`inputs: ["project://pricing"]` fixed it, and the hash now moves with the
crate.

The failure mode is the dangerous kind: nothing errors, the build stays
green, and the demonstration the repo exists to make — that a Rust change
invalidates the Elixir suite above it — is quietly false.

It is also the kind that recurs. The Gleam edge was built in Stage 5 with the
`dependsOn` and the task-level `deps` but no `project://` input, and shipped
that way: a `timeline/src/timeline.gleam` edit left `timeline_facade:test` on
an unchanged hash, replaying a stale pass, and the staleness reached
`server:test` through the facade. Stage 8 found it while writing this ADR and
fixed both. Whoever adds the next cross-language edge should read this as the
default outcome of declaring only the ordering, not as a one-off.

## Consequences accepted

- The edge is written in two places per consumer, which is duplication a
  reader will want to delete. The moon.yml comments say why it is not
  redundant.
- `project://` inputs are coarse: the whole project's files, not just the
  ones that matter. That is the right bias per seed.md §1 ("bias broad until
  hit rates hurt").
- Where a producing task *does* declare outputs (`server:openapi`,
  `core-api-client:build`), both mechanisms are in play and agree. The
  `project://` input is kept there anyway, so the rule is uniform rather than
  conditional on whether a given task happens to have outputs today.

## Alternatives considered

**Give `pricing:test` an `outputs` entry so the task-dependency hash works.**
Rejected: it would mean inventing an artefact for a task that legitimately
produces none, to work around a hashing rule rather than to describe the
build.

**Rely on Moon's affected-detection in CI and accept stale local caches.**
Rejected: seed.md §7's hermeticity posture is that under-declared inputs must
surface as failures, and the same task hash runs locally and in CI.

# ADR-0011: What CI treats as affected

**Status:** Accepted
**Date:** 2026-09-07
**Stage:** 12

## Context

`moon ci` was run as `moon ci --summary detailed`. Six pull requests, each
changing one file in a different tier, measured what that resolved:

| change                      | targets | `moon ci` |
|-----------------------------|---------|-----------|
| `README.md`                 | 0       | nothing   |
| `explorer/src/model.ts`     | 3       | 17s       |
| `web/src/api.ts`            | 3       | 26s       |
| `pricing_native/…/lib.rs`   | 2       | 9.5s      |
| `billing/lib/billing.ex`    | 3       | 4m 13s    |
| `core/mix.lock`             | 2       | 4m 10s    |

The Rust row is the defect. `server` depends on `pricing_native` as a Mix path
dependency and `server:test` declares `pricing_native:build` as a task
dependency, and `server:test` did not run. No consumer of a changed project
ran, in any of the six.

`README.md` claims this repository proves the opposite: "A breaking API change
fails the consumer's build. The PWA depends on a client generated from the
`server:openapi` output." With no consumer in the affected set, the pull
request that breaks the client cannot fail.

## Decision

`moon ci --include-relations --downstream deep`.

`--downstream` alone does nothing. `moon ci` compares changed files until `-g`
is given; the flag was on the command line of run 34144200711 and that run
still resolved 2 targets. Measured with `moon query tasks --affected` on the
same one-file Rust change:

| `--downstream` | tasks |
|----------------|-------|
| `none`         | 2 — `pricing_native:build`, `pricing_native:test` |
| `direct`       | 6 — adds `server:test`, `server:openapi`, `server:release`, `server:image` |
| `deep`         | 14 — adds `core-api-client:build`, `e2e:test`, `web:*`, `mobile:*` |

`deep` over `direct` because `core-api-client:build` is only in the deep set,
and it is the task that makes the claim above provable. `direct` is about four
minutes cheaper and buys a property this repository advertises and could not
demonstrate.

## Consequences accepted

A scoped pull request costs 8 to 12 minutes rather than 9 seconds to 4
minutes. The 9 seconds were not a saving; they were work not done.

The residue is not Elixir compilation. After ADR-0010 the long poles on a
one-line Elixir change are `server:release` at 4m 56s, `server:image` at 3m
58s and `mobile:build-android` at 3m 14s, against `server:test` at 23s.
`server:release` runs its own `mix deps.get --only prod`, a third dependency
tree that ADR-0010's `deps` task does not build. That is the next cost to
take, and it is not an affected-set question.

`root:sandbox-image` enters the set for a Rust change. That is correct:
`server:image` builds from it.

## The pull-request cache may fall back by key prefix

Item 5 of the CI plan asked for no `restore-keys` prefix fallback on anything
Moon replays. Item 4 of the same plan asked for `restore-keys:
moon-outputs-`. They contradict, and the fallback is kept.

Moon names each output archive after the task hash that produced it:
`billing:deps` hashing `bffc74bb` is served only by
`.moon/cache/outputs/bffc74bb….tar.gz`. Restoring an older `main`'s cache adds
archives to consult; it cannot change which one a task accepts, because the
task recomputes its own hash and looks for that name. A prefix fallback can
therefore only produce a miss or a valid hit, never a wrong replay.

What it does concede is a *stale miss window*: a pull request may restore a
cache old enough to hold nothing it needs, and pay a cold run. That is a cost,
not a correctness concern, and the nightly whole-graph run bounds it.

## Alternatives

- **`--downstream direct`.** Four minutes cheaper. Rejected: it leaves
  `core-api-client:build` out, which is the one task that proves the API
  contract claim.
- **`--downstream none` with a nightly deep run.** Rejected: a pull request
  could merge a change that breaks every consumer and CI would report green.
  The point of the affected set is to fail the pull request.
- **Declaring the consumers by hand as task dependencies.** Rejected for the
  reason ADR-0010 gives: it is the hand-maintained graph seed.md §2 exists to
  remove.

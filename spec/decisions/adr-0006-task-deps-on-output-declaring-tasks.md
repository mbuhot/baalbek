# ADR-0006: Cross-project edges are task deps on output-declaring tasks

**Status:** Accepted. Supersedes adr-0002. Amended by adr-0010: the `build/`
output paths gained an environment segment, and an Elixir artefact is no
longer only a marker.
**Date:** 2026-09-07
**Stage:** mid-build, after Stage 9

## Context

adr-0002 made every cross-language edge a `project://<id>` entry in the
consuming task's `inputs`. That convention produced three defects, all
observed in this repository.

**It is not transitive.** `project://timeline_facade` folds in the facade's
own files. It does not reach the Gleam source behind the facade. Nothing
reports a missing transitive edge; the result is a cache hit replaying a
stale pass. The shape bit twice — the Rust edge in Stage 4, and the Gleam
edge in Stage 8, where adr-0002 itself wrongly recorded the input as
present.

Both had been patched by hand before this ADR, which is what made the
convention look survivable. Precisely: at the commit this ADR was written
against, the Gleam edge did reach `server` — through the four
`/timeline/**` globs pasted into three tasks, plus a `deps` on
`timeline:package`, which already declared outputs. The edge still stale at
that commit was the Rust one: `core-api-client:build` keyed on the
*content* of `openapi.json`, so a comment-only change in the `pricing`
crate left it, and the whole TypeScript tier, on a cache hit. Each patch
held one edge and taught nothing about the next.

**It is coarse.** `project://` walks the whole target directory, gitignored
build trees included. `server:release` once hashed 23,094 files, 15,027 of
them `_build/**`, so it never hit its cache, and running `billing:test`
changed its key. The `hasher.ignorePatterns` block existed only to hold
that back.

**It races.** One task hashing a directory tree another task is rewriting
fails outright with `Failed to read path`. Working around it meant
hand-narrowing `project://timeline` to four source globs, and
`project://server` to a single file — which is the convention conceding
that it does not work.

## Decision

Every task another task depends on declares real `outputs`. A cross-project
edge is a task `deps:` entry on an output-declaring task. No task declares
another project's files as `inputs`.

Where a project had nothing to depend on, it gained a real build task:

| Project | Producing task | Declared output |
|---|---|---|
| `pricing` | `build` | `build/libpricing.rlib` |
| `pricing_native` | `build` | `build/lib/pricing_native/ebin` |
| `core`, `identity`, `billing`, `timeline_facade` | `build` | `build/lib/<app>/ebin` |
| `timeline` | `package` (existing) | `build/otp` |
| `server` | `openapi` (existing) | `priv/static/openapi.json` |
| `core-api-client` | `build` (existing) | `src/generated/schema.d.ts` |
| `web` | `build` (existing) | `dist` |

A test task is not a dependency target. `pricing:test` and `timeline:test`
were removed from their consumers' `deps` and replaced by `pricing:build`
and `timeline:package`.

## Why this works, measured

Moon does not hash a dependency's output *files*. It folds the dependency
**task's own hash** into the dependent's, and that hash is computed from
the dependency's declared **inputs**, command, environment, toolchain
versions and its own dependencies' hashes. A dependency with an empty
`outputs` list contributes nothing. `moon hash` prints this directly — the
old `server:test` manifest read:

```json
"deps": { "timeline:bootstrap": "ignored",
          "timeline:package": "89c9cafd5282db38..." }
```

`timeline:bootstrap` declares no outputs and is literally recorded as
`"ignored"`. That single word is the whole of adr-0002's problem.

Because the contribution is the upstream *hash*, it composes. A change to C
changes C's hash, which changes B's, which changes A's, without A knowing C
exists. A probe project confirmed the rule in isolation: a producer whose
output file was the constant string `FIXED` — byte-identical across runs —
still moved its consumer's hash when the producer's own inputs changed,
while an otherwise identical producer declaring no outputs left the
consumer on a cache hit.

So this is upstream-hash propagation, not content addressing. The plan was
drafted the other way round, describing the change as content-addressed and
therefore *less* eager than `project://`; the measurement says otherwise,
and PLAN.md now carries the correction. A change that leaves the compiled
artefact byte-identical still re-runs everything downstream. Precision
comes from the narrower input globs each producing task declares, not from
comparing artefacts — which is why this ADR is named for the edge, not for
the artefact.

## Why the Elixir apps compile into `build/`, not `_build/`

The Elixir apps were the hard case, and the first attempt declared
`_build/dev/lib/<app>/ebin`. Two objections, one of which turned out not to
be real:

**The one that is not real.** A prod-only change (`config/prod.exs`, or a
`Mix.env() == :prod` branch) cannot leave a dev artefact stale and skip a
release, because the artefact is never hashed. Editing `core/config/prod.exs`
moves `core:build`'s hash and re-runs `server:release` while
`core/build/lib/core/ebin` stays byte-identical. Measured, not assumed.

**The one that is real.** In a poncho layout no consumer consumes a
sibling's build tree — `server` recompiles every path dep into its own
`_build/<env>`. So any Elixir artefact is a marker, not a hand-off, and a
marker must not sit in a tree someone else owns. `_build/dev` is shared with
Mix, ElixirLS and a developer's own `mix compile`; declaring part of it as a
Moon output means a cache restore writes `ebin` files back without the
matching `.mix` compile manifests.

Both concerns resolve the same way: `MIX_BUILD_PATH=build` with `MIX_ENV`
pinned. `MIX_BUILD_PATH` replaces Mix's `_build/<env>` root wholesale, so
the declared output path names no environment, and the tree belongs to the
Moon task alone. The pinned `MIX_ENV` is then required, not optional — two
environments would otherwise share one directory. It also aligns the Elixir
apps with `timeline`'s `build/otp` and `pricing`'s `build/`: every project's
Moon-visible artefact now lives in `<project>/build/`.

`pricing_native` has a genuine artefact — `priv/native/pricingnative.so`,
which Rustler writes into the source tree and the release loads — and it is
still **not** declared, for the same rule stated one paragraph up. Rustler
writes that path from `pricing_native:test` and from `server`'s own
compiles too, and those run concurrently with `build` under `moon ci`;
declaring it would let Moon restore a cached copy over a tree another task
is writing. The marker ebin alone satisfies the non-empty-outputs
requirement.

The same candour is owed to Rust. `pricing:build`'s
`build/libpricing.rlib` is a debug-profile copy that nothing links:
`pricing_native`'s NIF rebuilds the crate from the Cargo path dependency
into its own `CARGO_TARGET_DIR` and links `libpricing-<hash>.rlib` from
there. So every marker in this repository is a marker, in all three
languages. The only declared outputs a consumer genuinely reads are
`timeline`'s `build/otp`, `server`'s `openapi.json`,
`core-api-client`'s `schema.d.ts` and `web`'s `dist`.

## The `hasher.ignorePatterns` interaction

`ignorePatterns` is **input-side only**. It filters the files Moon hashes as
a task's inputs; it has no effect on `outputs`, which are archived and
restored normally. Measured three ways: a probe producer whose output lived
under an ignored pattern still moved its consumer's hash; `core:build`'s
output under `**/build/**` moves `server:release`; and deleting
`core/build/lib/core/ebin` and re-running restores all 14 files from the
cache archive byte-for-byte.

So declaring an output inside an ignored tree is not a contradiction. With
that established, the block was cut from seven patterns to two. Its original
justification — holding back what `project://` dragged in — is gone with
`project://`. What remains are the two source globs that genuinely straddle
a build tree: `pricing_native`'s `native/**/*` covers the NIF crate's
in-tree `target/` (39 files), and `mobile`'s `android/**/*` covers the
Gradle directory that task writes its own APK into. `_build/`, `deps/`,
`node_modules/`, `dist/` and `priv/native/` are no longer reachable from any
declared input glob.

## Consequences accepted

- **An under-declared `outputs` list is the new silent failure.** A
  producing task that forgets `outputs` reverts its consumers to the
  adr-0002 defect, and nothing errors. The mitigation is that the
  consequence is now local and visible: `moon hash <hash>` prints `ignored`
  next to the dead edge, where previously the missing input was invisible
  by construction. Adding a checker was rejected — see below.
- **The whole TypeScript and mobile tier now rebuilds on any BEAM or Rust
  change.** Previously `core-api-client:build` keyed on the content of
  `openapi.json`, so a comment in the `pricing` crate left it cached. Now a
  one-line Rust edit moves `core-api-client:build`, `web:build`, `web:test`
  and re-runs the Gradle Android build. That is safe over-invalidation and
  the direct price of transitive correctness, but it is a recurring cost on
  every cross-tier change, not a one-off.
- **Single-target local gates are weaker.** `moon run pricing_native:test`
  no longer runs `pricing:test`, and `moon run timeline_facade:test` no
  longer runs `timeline:test`; a test task is not a dependency target, so
  those edges went. Both PLAN.md stage gates name both targets explicitly
  and `moon ci` runs every affected suite, so no coverage is lost — but a
  developer running one target by hand now proves less than before.
- **Four Elixir apps compile twice**, once into `_build/<env>` for their own
  test task and a developer's tooling, once into `build/` for Moon. Roughly
  50 seconds per app cold, cached thereafter, and parallel.
- **A dev-environment compile stands in for a prod consumer.** Accepted
  because the artefact is not hashed; the edge rides on inputs that cover
  prod, test and dev sources alike.
- **`server:image` and `e2e:test` still carry no hashable edge**, because a
  Docker image in the local daemon is not a file output. Both are
  `cache: false`, so there is no cache to go stale, and affected-detection
  reaches them through the project graph.
- The `moon.yml` files no longer say the same edge twice. adr-0002's
  duplication is gone.

## Alternatives considered

**A checker asserting every transitive edge is declared.** Rejected by the
project owner: a tool that detects the missing edge keeps the fragile
convention in place. The graph should make the edge impossible to miss, not
detectable after the fact.

**Narrowed cross-project input globs** (`/core/lib/**/*` and friends, the
shape `timeline_facade` and `core-api-client` had already been forced into).
Precise and race-free, but flat: every consumer must hand-list every project
behind every facade. That is the defect, restated.

**Per-environment compile tasks** (`core:build-prod`, `core:build-test`).
Rejected: three tasks with identical inputs produce three hashes that all
move together, so it triples the compile cost and changes no outcome.

**An `_build/*/lib/<app>/ebin` glob spanning environments.** Rejected: it
would sweep `_build/test`, produced by a *different* task, into this task's
cache archive.

**Concluding that Elixir needs a different mechanism entirely.** Considered
seriously, and rejected for lack of a candidate: a non-empty `outputs` list
is the only lever Moon offers. The honest half of that conclusion — that the
Elixir artefact is a marker rather than a hand-off — is recorded above
instead of hidden.

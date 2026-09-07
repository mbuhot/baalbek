# ADR-0009: Where CI runs `moon ci`, and what it may replay

**Status:** Draft. The shape decision is pending a measurement; the cache rule below is in force.
**Date:** 2026-09-07
**Stage:** 12

ADR-0007 stands. This ADR does not supersede it, and will only do so if the
measurement named under "Pending" comes out one particular way.

## Context

ADR-0007 ran `moon ci` inside the sandbox image so that an under-declared task
input, or a task reaching a binary the image does not carry, failed
immediately. That decision earned its place: five defects in this repository
were only ever visible to a cold run in the image, and four of the five were
masked by something warmer than production. Two of the five were specifically
`ubuntu-latest` supplying a binary the image lacks — `npx cap sync android`,
and `keytool` resolving to a system JDK.

ADR-0008 then took the four-minute Erlang/OTP compile off the hot path by
publishing the image to GHCR and importing its layers as a BuildKit cache
source. Measured on a real run with GHCR seeded: the image step is **62 seconds
on a cache hit against 2m48s cold**, and `Installing asdf:erlang` appears zero
times.

So the image is no longer what makes CI slow. What makes CI slow is that
nothing restores what a previous run built. A full-graph run takes **36m37s**
and an affected run of two targets about **10 minutes**, because each of the
six Elixir projects compiles the Ash dependency tree into its own `_build`
every time. ADR-0007 chose that deliberately: "Moon's own task cache is never
restored … a fresh `.moon/cache` on every run is what makes an under-declared
input fail rather than pass on a stale hit."

Two separate questions follow, and only one of them is answerable from a desk.

## In force: first-party build output is replayed on pull requests only

| Event | Restores `.moon/cache` | Saves `.moon/cache` |
|---|---|---|
| push to `main` | no | yes, keyed `moon-outputs-<shape>-<sha>` |
| pull request | yes, exact base sha then prefix `moon-outputs-<shape>-` | **no** |

The asymmetry is the whole design, not an optimisation of it.

- `main` restores nothing, so it stays the probe that fails on an
  under-declared input. It is also the only writer, so every artifact a pull
  request can replay was built by a genuinely cold run.
- A pull request never writes, so it cannot replay another pull request's work.
  GitHub's own cache scoping says the same thing a second time: a pull request
  reads its own ref and its base branch, nothing else.
- The prefix `moon-outputs-<shape>-` is the only place in this repository where
  moon may replay from a key that is not an exact match. It buys the common
  case — a branch cut a few commits behind `main` — and it is bounded below by
  `main` always being cold.
- **The shape is part of the key.** The two shapes compile against different
  libc, so replaying one shape's output into the other is how a green run ships
  a broken artifact. Without the shape in the key, running the experiment below
  would itself be the defect.

Accepted with it: GitHub's 10 GB per repository and roughly a week's eviction
mean occasional fully cold pull-request runs. Slow, never incorrect.

A restored cache carries `main`'s `ciReport.json`, which the workflow deletes
before running, so an aborted run cannot upload the wrong report as its own.

### Where that cache lives, in both shapes

`.moon/cache` is a symlink to `/tmp/baalbek-sandbox-moon-cache` in both shapes,
so every step that touches moon's cache is shape-independent. The native shape
writes through the symlink; `run-in-sandbox.sh` resolves it with `readlink -f`
and mounts the target at the same absolute path inside the container.

Verified locally, seeding the host directory as `actions/cache/restore` would
and then reproducing the container's exact mount shape:

```
--- .moon/cache resolves inside the container:
lrwxrwxrwx  .moon/cache -> /tmp/symtest2/hostcache
--- restored contents visible to moon:
.moon/cache/: ciReport.json  outputs
.moon/cache/outputs: abc123.tar.gz
--- read a restored output archive:
archive
=== host side after the container exits ===
written-by-moon-ci
```

That run also found a **pre-existing defect in the workflow's report upload.**
A bind mount whose target sits inside another bind mount writes through to the
mount source, and Docker creates the target as an empty directory. So the
container's `.moon/cache` writes have always landed in
`/tmp/baalbek-sandbox-moon-cache`, while `ci.yml` uploaded
`.moon/cache/ciReport.json` — the empty mountpoint. With
`if-no-files-found: ignore`, that step has reported success and uploaded
nothing. Both halves are fixed: the path is the mount's host path, and the
setting is `warn`.

## Pending: which shape CI should use

Both shapes are implemented, and `ci.yml` selects between them with a
`workflow_dispatch` input defaulting to `image`. Everything neither shape
selects is shared, down to the `moon ci` invocation itself, which is prefixed
with a variable that is empty in the native shape.

The desk argument against the native shape is strong and is recorded here so
the measurement is not confused for the reasoning:

- Item 2 of the plan that produced this work was premised on the image costing
  four minutes per run. ADR-0008 had already removed that. What the native
  shape buys is therefore the 62-second image import, and only on pull requests
  whose affected tasks do not reach `root:sandbox-image`.
- What it costs is putting `npx`, `npm`, `keytool`, a system JDK and a system
  Node back on the per-pull-request path — the exact shape of two of the five
  defects in the ledger. A nightly image gate does not recover that: a pull
  request could merge a toolchain leak and it would surface the next morning.

What that argument cannot supply is the number. So:

**The two numbers that settle it.**

1. **Shape overhead, cold.** The `moon ci` step's wall clock for
   `shape=image` against `shape=native`, dispatched twice against the same
   commit with `base` empty, so both run the whole graph with no output cache.
   This isolates what each shape costs: the container's mounts and chown
   against the native shape's apt pass and `~/.proto` restore.
2. **Per-pull-request wall clock, warm.** A pull request in each shape once
   `main` has seeded that shape's `moon-outputs-` cache, together with whether
   the native run skipped the image resolve.

If the native shape saves little, it is rejected on the ledger argument and the
per-pull-request environment check stays. If it saves several minutes, the
trade is genuinely open and worth paying for differently — for instance by
masking `npx`, `npm` and `keytool` on the runner, which is drift-prone and was
declined as speculative, but becomes worth its cost if the saving is large.

Neither run has happened. Both cache keys are namespaced by shape, so the two
sets of runs cannot contaminate each other, and the first run of each shape
also has a cold downloads cache under its own key — so each shape needs two
runs before its warm number means anything.

### What building the native shape cost, as evidence

The work is kept rather than discarded, because it is the difference between a
guess and a measurement, and because two of its findings are facts about this
workspace regardless of which shape wins.

- **`bash -l` loses PATH on the runner.** Every `toolchain: "system"` task is
  `bash -lc`, and both Debian's and Ubuntu's `/etc/profile` reset PATH
  unconditionally. In a pristine `debian:bookworm-slim`, `grep -n PATH
  /etc/profile` returns lines 5, 7 and 9. The image solves this with
  `/etc/profile.d/proto.sh`; the native shape has to install the same file, or
  every `mix` and `erl` in the workspace resolves to nothing.
- **proto's shims cannot locate an asdf-backend executable.**
  `~/.proto/shims/erl` fails with `expected file
  .../tools/erlang/28.4.3/erlang does not exist`, while `~/.proto/bin/erl`
  works. `erl`, `elixir` and `mix` work only from `bin`; `pnpm` exists only in
  `shims`. So `$PROTO_HOME/bin` must precede `$PROTO_HOME/shims`, and the order
  is load-bearing rather than cosmetic.
- **A `~/.proto` cache does avoid the OTP build.** Against a replica of
  exactly the three paths `setup-toolchain` caches — `plugins`, `tools`, `id`,
  and no `backends` at all — `proto install` completed in **2.851s** reporting
  `asdf:erlang 28.4.3 installed`, and `bin/erl` from the restored tree reported
  `erts 16.3.1 / otp 28`. `proto install` regenerates `bin` and the shims.
- **rustc stops being frozen by the image.** proto's rust plugin is a rustup
  wrapper: `~/.proto/tools/rust/` holds a manifest and nothing else, and
  `cargo` resolves from `~/.cargo/bin`. In the image, `stable` is whatever the
  image was built with; on the runner it is whatever `ubuntu-latest` ships.
  `moon-elixir-plugin:build` survives it only because its gate asserts
  provenance rather than bytes. This is a consequence of the native shape
  alone, and it disappears if that shape is rejected.
- **`.github/scripts/affected-needs-sandbox-image.sh` exists for the native
  shape only.** It asks moon whether `root:sandbox-image` — the only task that
  produces the image — is in the affected closure, and skips the 62-second
  import when it is not. Under the image shape an in-image run always needs the
  image, so the predicate is short-circuited rather than consulted. It is part
  of what is being measured; if the native shape is rejected, it goes with it.

## Kept regardless of the outcome

These are improvements on their own terms and neither shape depends on them.

- **`scripts/install-os-deps.sh`.** One package list, previously inline in the
  Dockerfile's two apt layers, now consumed by those layers and — in the native
  shape — by the runner. Names are resolved against the apt index rather than
  hardcoded, because Ubuntu's 64-bit `time_t` transition renamed six of the
  Chromium libraries. Verified in real containers of both distributions with
  the installer stubbed: `debian:bookworm-slim` resolves both groups to exactly
  the lists the Dockerfile carried, package for package, and `ubuntu:24.04`
  resolves all six alternates to their `t64` names, reaches
  `postgresql-client-17` and `libpq-dev` through PGDG's `noble-pgdg` suite, and
  simulates an install of all 181 resulting packages successfully.

  Two bugs surfaced from those runs. `apt-cache show | grep -q` races on
  SIGPIPE under `set -o pipefail` and reports a present package absent, so the
  output is captured whole. And a `return 1` from inside a process substitution
  cannot fail its caller, so a truncated package list installed silently; the
  result is returned in a global instead.

  What each group holds:

  | Group | Holds | Why |
  |---|---|---|
  | `toolchain` | `build-essential`, `git`, `curl`, `wget`, `ca-certificates`, `gnupg`, `lsb-release`, `pkg-config`, `unzip`, `xz-utils`, `file`, `locales` | Compilers, and fetching proto's own `.tar.xz` releases. |
  | `toolchain` | `autoconf`, `m4`, `libncurses-dev`, `libssl-dev`, `unixodbc-dev`, `libsctp-dev`, `zlib1g-dev` | OTP's own required plus commonly-needed optional list. wxWidgets and the doc toolchains are omitted: a wx-based OTP application's *build* hard-fails without the headers rather than degrading, so `KERL_CONFIGURE_OPTIONS` disables `wx`, `debugger`, `observer` and `et` explicitly. |
  | `toolchain` | `postgresql-client-17`, `libpq-dev` | Debian bookworm's own repositories stop at the Postgres 15 client, so PGDG is added for 17. |
  | `tasks` | `python3` | `root:test` runs `test-paths.py`, every Elixir app's `mix test.changed` calls it, and two shell scripts parse `moon query` output with it. |
  | `tasks` | 22 Chromium libraries, `fontconfig`, `fonts-liberation` | playwright-core 1.63.0's own `debian12` set, read out of its `nativeDeps` table rather than guessed. |
  | `tasks` | `docker-ce-cli`, `docker-buildx-plugin`, `docker-compose-plugin` | Four tasks shell out to `docker`. Without Buildx, `docker build` degrades to the legacy builder, which shares no cache with the daemon's BuildKit. |

  The cost: single-sourcing the list means the script is COPYed above `proto
  install`, so a package added to either group invalidates the OTP layer in a
  cold-cache build. This supersedes PLAN.md's "Adding OS packages after the
  fact" rule. GHCR pays it once, on `main`; an arm64 developer still pays it
  locally, because only amd64 is published (ADR-0008). Two scripts would
  restore the old layer split, and that is the change to make if the arm64
  rebuild becomes the thing that hurts.

- **The image's inputs are inputs to every task.** `.moon/tasks/all.yml` puts
  `Dockerfile`, `.dockerignore` and `scripts/install-os-deps.sh` in
  `implicitInputs`, so an environment change invalidates the whole graph rather
  than only the image tasks — which matters much more now that pull requests
  replay output. `.devcontainer/docker-compose.yml` is there too: a Postgres
  bump changes what every suite proves without changing any task's own inputs,
  so without it a bump would run zero tasks and leave every cached test result
  standing.

  That file has to be `.moon/tasks/all.yml`. moon 2.5.4 **silently ignores**
  `.moon/tasks.yml`: neither an unknown key nor a wrong type in it produces an
  error, and the setting has no effect. Naming `implicitInputs` also does not
  displace moon's built-in `/.moon/*.yml` glob, which is added regardless, but
  that glob is one level above this file — hence the explicit
  `/.moon/tasks/*.yml` entry. Confirmed reaching `root:test`, `core:build` and
  `web:build`.

- **`.github/workflows/image-gate.yml`.** Runs every task in the workspace
  inside the image with nothing restored — no toolchain cache, no downloads, no
  `.moon/cache` — nightly, on a push to `main` that touches the environment,
  and on demand. It is the only run that is now literally cold: `main` restores
  no task output but does restore the Cargo target trees and Gradle's
  `modules-2`, which are third-party build state rather than declared outputs.

- **`.github/scripts/summarize-ci-report.sh`.** Prints what a run did —
  executed against replayed against skipped, the affected projects and the
  files that selected them, and the slowest executed tasks — into the log and
  the step summary. With pull requests now replaying output, "did this change
  do minimal work" is the question every run has to answer, and it should not
  require downloading an artifact.

- **`pnpm-workspace.yaml` sets `storeDir: "~/.cache/pnpm/store"`**, inside the
  one directory CI caches and `run-in-sandbox.sh` mounts. pnpm 11 reads this
  setting **only** from that file — verified: `store-dir` in `.npmrc`,
  `npm_config_store_dir` and `PNPM_STORE_DIR` are all ignored, while `~` and
  `${HOME}` in `storeDir` both expand. The devcontainer's `.pnpm-store` named
  volume is now unused; it effectively already was, since pnpm's default store
  is under `$HOME` and fell back to the in-tree path only where `$HOME` and the
  workspace sit on different devices.

- **CI's Postgres is the devcontainer's service.** Both workflows run
  `docker compose -f .devcontainer/docker-compose.yml up -d --wait postgres`
  rather than a `services:` block copying it, so the image, the credentials and
  the healthcheck exist once — and that file being an implicit input is what
  makes a version bump a cold-graph event by construction rather than by
  anyone remembering. It costs a serial step where `services:` started in
  parallel with the checkout.

## Alternatives considered

**Save the moon cache from pull requests too.** Rejected, and this is the one
line that cannot move. A pull request that writes turns the cache into a
peer-to-peer channel: a branch with a broken input declaration would seed an
artifact another branch replays, and `main` would stop being the floor under
what any run can trust.

**A prefix restore key on `main`.** Rejected for the same reason. `main` cold
is what makes the pull-request prefix sound; giving `main` a fallback removes
the floor and leaves only the fallback.

**Deciding the shape from the argument alone.** This was done once, in both
directions, and reversed both times. PLAN.md's item 2 asserted the native shape
on a premise ADR-0008 had already invalidated; the counter-argument then
rejected it without a run, one message after CLAUDE.md gained the rule that a
measurement showing no difference is a finding rather than a footnote. The rule
applies to the rejection as much as to the proposal, which is why both shapes
are implemented and neither is asserted here.

**`cache-base: main` on `setup-toolchain`.** It would stop pull requests
writing the toolchain cache. Rejected: a pull request that changes
`.prototools` would then rebuild Erlang/OTP on every push to that branch. The
toolchain is a download, not a task output, so nothing is gained.

**A checker asserting the runner and the image install the same packages.**
Rejected: one script consumed by both removes the question instead of policing
it, which is ADR-0006's reasoning applied again.

## What is not verified

Nothing here has run on GitHub. What was checked locally, on an **aarch64**
host against a real Docker daemon and the real workspace, is every measurement
quoted above, plus:

- A restored host directory visible at `.moon/cache` inside the container,
  including `outputs/*.tar.gz`, and the container's writes landing where
  `actions/cache/save` and `upload-artifact` read them.
- `ln -sfn` being idempotent across repeated runs of its step, and replacing a
  symlink rather than nesting inside it.
- `!scripts/install-os-deps.sh` reaching the build context through the deny-all
  `.dockerignore`: a `find` in the built context lists exactly `.prototools`
  and that script.
- `docker buildx build --check` on the rewritten Dockerfile: no warnings.
- The affected predicate answering no for a workflow-only commit and yes for a
  `Dockerfile` change.
- The `RUN_PREFIX` expression, which was wrong on the first attempt in a way
  that would have invalidated the whole experiment: GitHub's `&&`/`||` return
  operands and treat `''` as falsy, so `cond && '' || x` yields `x` for both
  values of `cond`. The native shape would have silently run inside the image,
  and the comparison would have measured the image against itself. The
  non-empty branch is now the true branch.
- `actionlint` accepts all four workflows and `shellcheck` accepts every
  script.

Unsettled until a real run: both numbers named under "Pending"; the whole apt
pass on a real runner, where most of the toolchain group is already installed;
`docker compose up -d --wait postgres` on a runner, since the local rehearsal
reached "Starting" and then failed to bind 5432 against this sandbox's own
Postgres; whether a `moon ci` run with no affected tasks writes a
`ciReport.json` at all; `mobile:build-android` on x86_64; and whether the
toolchain cache and the outputs cache fit the 10 GB budget together —
`~/.proto/tools` is 1.2 GB uncompressed here and a full local `.moon/cache` is
1.2 GB, of which 805 MB is archived outputs.

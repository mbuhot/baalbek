# ADR-0008: The sandbox image is published to GHCR, and one builder writes the cache

**Status:** Accepted.
**Date:** 2026-09-07
**Stage:** 12

## Context

ADR-0007 put `moon ci` inside the sandbox image and accepted one cost
explicitly: "A cold CI run compiles Erlang/OTP from source. An ephemeral runner
has no Docker layer cache, and nothing here restores one." It also named the
fix and declined to take it, because publishing a package is the repository
owner's call rather than a build one. That call has now been made.

The first real run took 7m15s, of which roughly four minutes was `proto
install` compiling OTP in the pre-build step. Every run pays it, because a
GitHub runner is a fresh VM with an empty Docker daemon, and the workflow used
a plain `docker build` with no cache backend and no registry.

That run is evidence about the pre-build step only. Its `moon ci` logged
`No tasks affected by changed files` and executed zero tasks, so
`root:sandbox-image` never ran on a runner at all. Everything below about the
two builders sharing a cache is measured locally, not inferred from it.

Two separate things were wrong, and only one of them was the missing registry.

### The two builders

`.github/workflows/ci.yml` pre-built the image with plain `docker build`, and
its comment claimed that as deliberate: legacy `docker build` "leaves the
daemon's own layer cache warm", so `moon ci` re-running `root:sandbox-image`
later would hit rather than compile OTP twice in one run. A later review moved
`root:sandbox-image`, `server:image` and `web:image` to `docker buildx build`
(ADR-0007 records why: a missing Buildx plugin should error, not silently
degrade). That left the workflow and the task naming two different commands for
the same build, and if the two write to different caches then a single CI run
compiles OTP twice.

**Measured, against a real daemon (Docker Engine 29.7.2, arm64), because the
answer decides whether that was a live bug.**

The two builders genuinely are separate stores. A three-layer synthetic
Dockerfile, built first with the legacy builder:

```
$ DOCKER_BUILDKIT=0 docker build --tag buildertest:legacy .
DEPRECATED: The legacy builder is deprecated and will be removed in a future release.
Step 2/3 : RUN echo "expensive-step-marker" > /marker && sleep 2
 ---> Running in 72422baefa3c
```

then, immediately after, with buildx on the same file:

```
$ docker buildx build --load --tag buildertest:viabuildx .
#5 [2/3] RUN echo "expensive-step-marker" > /marker && sleep 2
#5 DONE 2.2s
```

`DONE 2.2s`, not `CACHED`. buildx re-executed a step the legacy builder had
just run.

On the real `Dockerfile` the same split costs the OTP build. The BuildKit store
held that layer, yet the legacy builder did not:

```
$ DOCKER_BUILDKIT=0 docker build --tag baalbek-sandbox:legacyprobe --file Dockerfile .
Step 13/22 : COPY --chown=vscode:vscode .prototools .prototools
 ---> Using cache
Step 14/22 : RUN proto install
 ---> Running in be88aae0c059
[rust] Rust stable installed (20s)
[java] Java temurin-21.0.12+8 installed (36s)
```

Steps 2–13 hit the classic store; `RUN proto install` did not, and started
rebuilding the toolchain. It was killed at that point.

**But the bug was latent, not live.** On Docker 23 and later, plain `docker
build` *is* buildx. `docker build --help` on this engine names the command
"docker build, docker builder build, docker image build, docker buildx build"
and accepts `--load`, `--cache-from`, `--cache-to` and `--builder`. Only
`DOCKER_BUILDKIT=0` selects the legacy path. So both commands were already
reaching one store:

```
$ docker build --tag baalbek-sandbox:latest --file Dockerfile .      # 0.155s
#13 [ 9/12] RUN proto install
#13 CACHED
$ docker buildx build --load --tag baalbek-sandbox:latest -f Dockerfile .   # 0.158s
#7 [ 9/12] RUN proto install
#7 CACHED
```

The 7m15s run did compile OTP exactly once — its log shows
`building with "default" instance using docker driver`, no `DEPRECATED` line,
and no second `proto install` anywhere in the `moon ci` step. But that step ran
zero tasks, so the second build never happened; the run is consistent with a
shared cache without demonstrating one. The demonstration is the pair of local
builds above.

The defect was that the workflow's stated reason for `docker build` was false —
the property it claimed comes from BuildKit, not from the legacy builder — so
the comment was defending a spelling that would have broken the moment anyone
set `DOCKER_BUILDKIT=0` or ran on an engine where the alias differs.

### What a pull does not do

The obvious registry fix is to pull the image and run it. It does not work
here, and the reason is the same cache split.

`docker pull` populates the daemon's **image** store. `moon ci` still runs
`root:sandbox-image`, which is `options: { cache: false }` and therefore always
re-executes, and that task runs `docker buildx build`. BuildKit keys on its own
cache records, not on image layers that happen to be present — ADR-0007 records
the same mechanism for the `docker-container` driver, where `--load` "would
import the final image and leave the daemon's cache cold". So a pull-and-run CI
moves the OTP compile out of the pre-build step and into `moon ci`. Net zero.

## Decision

### One builder, named the same everywhere, and pinned

The workflow's image step uses `docker buildx build --load`, matching all three
image tasks. `--load` is explicit rather than relied upon, in the workflow and
in all three tasks, so the image reaches the daemon for `docker run` regardless
of the exporter default. The stale comment is replaced.

All four invocations also pass **`--builder default`**. ADR-0007 requires the
`docker` driver and left it as prose; this makes it enforcement. The flag is
not the one-sided guard that was first rejected, because it goes on both sides
of the pair — and it cannot false-negative the way a checker would:
`docker/setup-buildx-action` creates a `builder-<uuid>` and makes it *current*
without renaming `default`, so a pinned flag keeps pointing at the daemon's own
BuildKit while an unpinned build would silently follow the new current builder
into a cache nothing else shares. An environment variable would not do:
`BUILDX_BUILDER=default` reaches the workflow but not the tasks, because
`run-in-sandbox.sh` passes a fixed allowlist of variables into the container,
which is exactly the asymmetry to avoid.

Verified inside the image, against the mounted socket:
`#0 building with "default" instance using docker driver`.

Verified afterwards, end to end: with the pre-build done by buildx,
`moon run root:sandbox-image` inside the container reports every layer
including `RUN proto install` as `CACHED` and completes in
`root:sandbox-image (208ms, dd00d7ae)`.

### The image is published to GHCR, and CI uses it as a cache source

`.github/workflows/sandbox-image.yml` builds and pushes
`ghcr.io/<owner>/baalbek-sandbox` on pushes to `main` that touch `Dockerfile`,
`.dockerignore` or `.prototools`, and on `workflow_dispatch`. It needs
`permissions: packages: write`.

CI does **not** pull that image and run it. It builds the current `Dockerfile`
with the published image as a `--cache-from` source. That single choice answers
both the speed question and the staleness question:

- The image CI runs is by construction the output of building the tree's own
  `Dockerfile`. It cannot be older than the tree.
- A registry image that does not match only costs cache misses at and below the
  first differing layer. It can never make CI test the wrong toolchain.
- The import lands in the local BuildKit store, so `moon ci`'s later
  `root:sandbox-image` is a hit without touching the registry at all.

Measured, with the published layers deliberately absent from the daemon's own
cache — pushed from a separate `docker-container` builder to a local registry,
so nothing warmed the default builder:

```
$ docker buildx build --load --cache-from type=registry,ref=localhost:5000/synth:v1 -t synth:local .
#6 [2/4] RUN echo layerA > /a && sleep 3
#6 CACHED
#7 [3/4] RUN echo layerB > /b && sleep 3
#7 CACHED
real 0m0.153s
```

and then the same build with **no** `--cache-from`, which is what
`root:sandbox-image` runs:

```
$ docker buildx build --load -t synth:local2 .
#5 [2/4] RUN echo layerA > /a && sleep 3
#5 CACHED
#6 [3/4] RUN echo layerB > /b && sleep 3
#6 CACHED
#7 [4/4] RUN echo layerC > /c
#7 CACHED
real 0m0.112s
```

The imported cache persists. That is the property the decision rests on.

The publish side needs no special builder: the default `docker` driver
supports `--push`, several `--tag`s, `--cache-from type=registry` and
`--cache-to type=inline` (observed: `preparing layers for inline cache done`).
Inline cache is what CI imports, and it survives buildx's default provenance
attestations — pushed with attestations on, the import still reported `CACHED`
— so no `--provenance=false` is needed.

### The immutable tag is a digest of the image's inputs and its architecture

Three tags are pushed: `:latest`, `:sha-<short sha>` for provenance, and
`:toolchain-<arch>-<digest>`, both parts from
`.github/scripts/sandbox-image-tag.sh` — one implementation, shared by both
workflows.

**The architecture is part of the tag, and file content alone is not enough.**
GitHub publishes from `ubuntu-latest`, which is amd64; this repository's own
development platform is arm64. A tag built from content only matches across
that boundary, and the probe cannot tell:

```
$ docker buildx imagetools inspect localhost:5000/archtest:toolchain-deadbeef ; echo "probe exit=$?"
probe exit=0
$ docker buildx build --builder default --load \
    --cache-from type=registry,ref=localhost:5000/archtest:toolchain-deadbeef -t archtest:local .
#6 [2/3] RUN echo archA > /a && sleep 4
#6 DONE 4.2s
#7 [3/3] RUN echo archB > /b && sleep 4
#7 DONE 4.2s
real 0m8.512s
```

An amd64 image, probed from an arm64 daemon: the probe succeeds, so the banner
would announce `CACHE HIT … every layer should be reused`, and then every layer
rebuilds. On the real image that is the full four-minute OTP compile, announced
as a hit, with the elapsed-time warning arriving four minutes too late. It also
meant the developer path this repository advertises could never work on its own
primary platform.

The arch comes from `docker version --format '{{.Server.Arch}}'` — the daemon's,
not the client's, because the daemon is what builds — and the script fails
rather than guessing if no daemon answers. A mismatch now reads as cold:

```
$ .github/scripts/sandbox-image-tag.sh
toolchain-arm64-97c6a048b9ba449b        # an ubuntu-latest publish writes toolchain-amd64-…
sandbox image: cannot use …:toolchain-arm64-97c6a048b9ba449b
sandbox image:   ERROR: …:toolchain-arm64-97c6a048b9ba449b: not found
sandbox image: COLD, no cache source resolved …
```

Publishing a multi-platform manifest is the other way to close this, and is the
obvious later move if arm64 CI or arm64 developer pulls become worth the build
time. Naming the architecture costs nothing and makes the honest answer the
default in the meantime.

A commit SHA is the wrong lookup key. The publish only runs on commits that
touch the three input files, so for almost every commit CI is on there is no
image tagged with its SHA. CI would have to walk history for "the last commit
that touched the Dockerfile", which is a second, drift-prone implementation of
a question the content already answers. A digest of the inputs is asked
directly: CI hashes its own three files and requests exactly that tag. Present
means byte-identical inputs; absent means nothing matches, and the run says so.

The digest hashes each path together with its content
(`sha256sum Dockerfile .dockerignore .prototools | sha256sum`), so moving a byte
from one input to another still moves the tag.

The tag's file list has to track `root:sandbox-image`'s `inputs:` by hand, and
that coupling is deliberately allowed to be loose, because of the property
above: **the tag can only be wrong about speed, never about correctness.**
BuildKit hashes the build's real inputs itself, so a file the tag script forgot
still changes the layer's cache key and still forces a rebuild. The tag is a
lookup hint, not a correctness claim.

Two further things make the drift narrow rather than merely harmless. The two
lists are currently identical. And the root `.dockerignore` is deny-all with a
single `!.prototools`, so the build context cannot gain an unhashed file
without a `.dockerignore` edit — which is itself one of the three hashed
inputs, and moves the tag. That is why no drift-checker guards this: the
failure it would catch is a slow build, and the design already makes the
dangerous version of it impossible.

### The three paths are announced

`.github/scripts/resolve-sandbox-image.sh` probes with
`docker buildx imagetools inspect` and prints a banner for whichever path it
takes — exact hit, partial hit on `:latest`, or cold. This is not decoration.
A `--cache-from` ref that is missing, or a registry that is unreachable, is
**not an error**:

```
$ docker buildx build --cache-from type=registry,ref=localhost:5000/nope:nope ... ; echo $?
0
$ docker buildx build --cache-from type=registry,ref=localhost:59999/nope:nope ... ; echo $?
0
```

Both exit 0 and build from scratch. Left alone that is a silent four-minute
regression, which is the exact failure mode this change exists to remove. The
probe has real exit codes (0 present, 1 missing, 1 unreachable).

**The probe's own message is printed, not discarded**, because the exit code
alone collapses three different problems into one banner. Never-published, an
unreachable registry and a rejected credential are the same `1`, and only the
message separates them:

```
sandbox image: cannot use ghcr.io/mbuhot/baalbek-sandbox:toolchain-arm64-97c6a048b9ba449b
sandbox image:   ERROR: failed to authorize: failed to fetch anonymous token: …: 403 Forbidden
```

Without that line an authentication regression on `main` is indistinguishable
from a first run before anything was published, and the banner's "nothing
usable in" would be a false statement about the registry's contents. The cold
banner now says the probe output explains why and that an absent image is not
the only cause.

A run that claims an exact hit and still takes over two minutes prints a
warning. It asks whether the layers were reused rather than asserting they were
not, because 120s is a guess: transferring this image's layers could
legitimately exceed it, and that number is one of the things this ADR admits it
has not measured.

## Alternatives considered

**`cache-from`/`cache-to: type=gha`.** No registry, no package, no new
workflow. Rejected on capacity: a 4.6 GB image with `mode=max` intermediates
is pitched against a 10 GB cache budget shared with every other cache in the
repository, and GitHub evicts by opaque LRU. The failure is not a clean miss,
it is a cache that works until the day something else fills the budget, and
then works again. A cache that sometimes works is worse than one that reliably
does not, because nobody investigates an intermittent slowdown. `actions/cache`
here is already restricted to named download directories for a related reason.

**Pull the published image and run it.** Rejected on the mechanism measured
above: a pull warms the image store, not BuildKit's, so `root:sandbox-image`
recompiles OTP inside `moon ci`.

**Pull *and* build with `--cache-from`.** Satisfies both, but transfers and
stores the same ~1.3 GB twice, into two separate content stores. ADR-0007
records disk as "the single most likely first failure" on a hosted runner, so
paying 1.3 GB for a cleaner probe exit code is the wrong trade. The
`imagetools inspect` probe costs a manifest.

**`docker save`/`docker load` through `actions/cache`.** ADR-0007 already
rejected this shape for the nested-daemon alternative. It has the `type=gha`
budget problem without the registry's benefit to developers.

**Tag by commit SHA as the lookup key.** Rejected above.

**A checker asserting the tag's input list matches moon.yml.** Rejected: the
list can only affect speed, and ADR-0006's reasoning applies — a checker that
props up a fragile convention is worse than a design where being wrong is
cheap.

## Why this is a new ADR and not a supersession of 0007

ADR-0007's decision — the job runs on the runner and invokes the image per
step — holds unchanged, as does every flag in `run-in-sandbox.sh`. What changes
is one *consequence* it listed as knowingly unaddressed, together with the
route out that it named. Its "Every build must use the default `docker` driver"
consequence also still holds, and this ADR depends on it: the pre-build and
`root:sandbox-image` share the daemon's BuildKit because both use that driver.
Marking 0007 superseded would tell a reader its reasoning had lapsed, which
would be false.

Two things in 0007 are nonetheless wrong, and because ADRs here are immutable
this is the only place that can be said.

**0007's prescribed fix was itself incorrect.** Its Consequences accepted
reads: "The fix is a registry-cached image: `root:sandbox-image` already reads
`SANDBOX_IMAGE`, and `run-in-sandbox.sh` passes it through, so *pulling*
`ghcr.io/<owner>/baalbek-sandbox` and tagging it locally is a change to the
workflow alone." The "What a pull does not do" section above disproves that. A
pull fills the image store, `root:sandbox-image` is `cache: false` and rebuilds
with BuildKit regardless, and BuildKit does not key on layers that merely
happen to be present — so pulling and tagging would have moved the OTP compile
into `moon ci` rather than removing it. The change is also not to the workflow
alone: it needs the registry used as a cache source, and it needs the publish
side to export inline cache.

**And the workflow comment 0007 left in place was wrong**, asserting that
legacy `docker build` keeps the daemon's BuildKit cache warm. 0007 states the
legacy-builder mechanism correctly for the Buildx-plugin-masked case inside the
image; relying on it on the runner was the mistake.

Neither touches 0007's decision, its four `run-in-sandbox.sh` flags, or its
`docker` driver requirement, so it is corrected here rather than superseded.

## Consequences accepted

- **Moon's task cache is still never restored.** Nothing here caches task
  output. The image is a toolchain, and a fresh `.moon/cache` every run is
  still what makes an under-declared input fail rather than pass on a stale
  hit. That property is untouched, and it is why the registry is used as a
  *layer* cache and nothing else.
- **`packages: read` has to be named in `ci.yml`.** Specifying any permission
  sets every unspecified one to `none`, so the repository's read-only default
  does not carry `packages` through. The first passing run's log shows exactly
  what the previous block granted:
  `GITHUB_TOKEN Permissions / Contents: read / Metadata: read` — no packages
  scope at all, so a pull would have failed 403 on this private repository.
- **A fork PR builds from source, by construction rather than by tolerance.**
  The login step is *skipped* when the PR head repository is not this one, so
  the fork branch takes the cold path deliberately. Everywhere else a failed
  login **fails the job**. An earlier version used `continue-on-error`, which
  made a real credential regression on `main` look exactly like a fork PR — a
  slow green run, which is the failure mode this whole change exists to
  eliminate. The alternative to skipping is exposing a registry credential to
  fork code, which is not on the table.
- **`:latest` is a partial cache source, and can be *newer* than the tree.** A
  PR branched before a `Dockerfile` change gets hits only below the first
  difference. Correct, and slower than an exact hit.
- **Only amd64 is published, so an arm64 developer always builds cold.** The
  publish runs on `ubuntu-latest`. The arch in the tag makes that honest rather
  than a false hit, but it does not make the developer affordance work on an
  arm64 machine — `README.md` says so plainly rather than promising a pull that
  will not happen. Publishing a multi-platform manifest is the fix when it is
  worth the build time.
- **The digest tag is immutable with respect to this repository, not to the
  world.** `FROM debian:bookworm-slim` floats, so the same tag can be rebuilt
  from a different base, and `workflow_dispatch` deliberately overwrites it.
  The tag means "built from these repo inputs", never "built from these bytes
  everywhere".
- **A change to the publishing machinery needs its own trigger.** The publish
  workflow's `paths` therefore lists itself and the tag script alongside the
  three image inputs. Without that a fix to the workflow would not run until
  someone next touched the toolchain, and `workflow_dispatch` would be the only
  way to exercise it.
- **The registry is touched only from the runner.** `docker login` writes the
  runner user's config; inside the image `$HOME` is `/home/vscode` and no
  credential is mounted. That is fine because `root:sandbox-image` needs no
  registry once the local BuildKit cache is warm, but it does mean an image
  task that ever wanted to push would need credentials passed in deliberately.
- **The publish job pays a full OTP compile whenever the toolchain changes.**
  That is the point: it is paid once, on `main`, instead of on every CI run and
  every developer's machine.

## What is not verified

Neither workflow has run on GitHub. What was checked locally, against a real
daemon and the real `Dockerfile`, is every measurement quoted above, plus a
rehearsal of all three paths of `resolve-sandbox-image.sh` against a local
registry — cold, partial and exact — each producing the real 4.9 GB image in
the daemon, and each printing the intended banner. `actionlint` accepts both
workflows and `shellcheck` accepts both scripts.

Unsettled until a real run:

- **Whether `permissions: packages: write` in the publish workflow is enough
  while the repository's `default_workflow_permissions` is `read`.** The
  evidence says yes and cannot prove it. The documented behaviour of the
  `permissions:` key is that it sets the token's scopes for that workflow; the
  only documented cap is an organisation-level restriction, and this repository
  is owned by a user account, so no organisation policy layer exists. The API
  exposes no maximum-permission field to inspect. If the first publish run
  fails with a 403 on push, the repository setting has to be raised to
  "Read and write permissions"; that is the owner's change to make, not this
  ADR's.
- **The first publish of the package.** A container package pushed by
  `GITHUB_TOKEN` is expected to be created private and linked to this
  repository, which is what makes `packages: read` sufficient for CI to import
  from it. If the link is not made automatically the package needs its access
  set once, by hand.
- **How long an exact-tag import of the real 4.6 GB image takes.** Inline cache
  completeness is settled: the pushed cache carried 14 records for this
  Dockerfile's 12 layers, and the import reused the final filesystem layer too,
  so it is complete for a single-stage build. What is unmeasured is the
  transfer time on a hosted runner relative to the four minutes it saves.
- **Disk.** The import adds the image's layers to BuildKit's store on a runner
  that ADR-0007 already measured as tight. It should be cheaper than a build,
  which writes the same layers plus an OTP build tree, but that is reasoning,
  not a measurement.

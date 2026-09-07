# ADR-0007: CI runs `moon ci` inside the sandbox image, from the runner

**Status:** Accepted.
**Date:** 2026-09-07
**Stage:** 12

## Context

PLAN.md's "Sandbox" section requires that the same image serve the devcontainer
and CI, "so an under-declared task input fails immediately". A GitHub-hosted
runner is the opposite of that: `ubuntu-latest` ships Node, Python, a JDK, gcc
and Docker, so a task that forgot to declare an input would find its tool
anyway and pass. The image is what makes the failure immediate.

The complication is that this workspace builds Docker images from Moon tasks.
`root:sandbox-image`, `server:image` and `web:image` each shell out to
`docker build`, `e2e:test` drives `docker compose`, and the chain
`e2e:test` → `server:image` → `root:sandbox-image` means a full `moon ci` builds
images from inside whatever environment it runs in. So the question is not
"which image" but "where does the Docker client live relative to its daemon,
and do the two agree about paths".

GitHub documents none of the mechanics that decide this. The facts below come
from the runner's own source (`actions/runner`, `src/Runner.Worker`), not from
the docs and not from memory:

- **The Docker socket *is* mounted into a job container.**
  `Container/ContainerInfo.cs` adds `MountVolume("/var/run/docker.sock",
  "/var/run/docker.sock")` unconditionally on Linux when `IsJobContainer`.
  Docker-outside-of-Docker therefore works in a `container:` job.
- **The workspace is mounted at a different path than it has on the host.**
  The same file maps the runner's work directory to `/__w`, its tool cache to
  `/__t` and its externals to `/__e`; `ContainerOperationProvider.cs` mounts
  those and sets `HOME=/github/home`. Inside the container `GITHUB_WORKSPACE`
  is `/__w/<repo>/<repo>`; the identical directory on the host is
  `/home/runner/work/<repo>/<repo>`.
- **The runner passes no `--user`,** so a job container runs as the image's
  `USER`. It does pass its own `--network`, `--workdir` and
  `--entrypoint tail -f /dev/null` (`Container/DockerCommandManager.cs`).

moon's own Docker guide covers `moon docker` scaffolding for building images; it
says nothing about running moon *inside* a CI container.

## Decision

The job runs on the runner. Each step that needs the image invokes it:

```
.github/scripts/run-in-sandbox.sh moon ci
```

Four `docker run` flags in that script carry the decision:

| Flag | Why |
|---|---|
| `-v /var/run/docker.sock:/var/run/docker.sock` plus `--group-add <socket gid>` | The client is in here, the daemon is out there. The image's `vscode` user is in no `docker` group, so the group is added at run time. |
| `-v "$WORKSPACE:$WORKSPACE" -w "$WORKSPACE"` | The workspace is mounted at *the same absolute path* it has on the host. `docker compose` resolves `./bootstrap.exs` against the compose file's directory and hands the result to the daemon, which resolves it on the host. Path identity is what makes those two answers the same string. |
| `--network host` | `e2e/docker-compose.yml` publishes the PWA on a host port and Playwright connects to `localhost:<port>`. Sharing the runner's network namespace makes those the same port, and puts the workflow's Postgres service on `localhost:5432` where every app's `config.exs` expects it. |
| `--user vscode` (the image default) | Everything proto installed — the toolchains, hex, rebar — lives under `/home/vscode`. The workflow chowns the checkout to uid 1000 rather than running the image as root. |

`moon ci` needs a base ref, so the workflow resolves one per event and passes it
as `MOON_BASE`: the PR base for a pull request, `github.event.before` for a
push, an input for a manual run, and nothing when that ref is not a commit in
the clone. The fallback is safe rather than quietly empty — with no `MOON_BASE`
on the default branch, moon treats the whole graph as affected and runs
everything.

**Moon's own task cache is never restored, and the container gets its own.**
Only downloads are cached, each named individually rather than a whole cache
root: Playwright's browsers, the Android SDK, the Cargo registry, hex's package
cache, Gradle's dependency cache, the redirected Cargo target directories. None
of those is a task output.

The container's separate cache is the second half of the same rule, and the
first version of this script got it wrong: it mounted the *host's* `.moon/cache`
into the container. Moon's task hashes are environment-independent — the same
task hashes identically inside and outside the image, verified on
`mobile:build-android` (`c7445ce2`) and `moon-elixir-plugin:build`
(`d1021dbc`) — so a shared cache lets the container replay hits the host
produced. A run like that proves nothing about whether the image can do the
work, which is the entire point of running in the image, and it is how a task
that cannot build in a fresh container passed this script's first outing. The
mount now points at a directory outside the download cache root, so nothing
restores it and CI starts cold every run.

Asking "does this image actually run CI" found five gaps in it, all fixed in
the layer appended after `proto install`. Every one was invisible from the
devcontainer, and every one would have failed a task:

- **No Docker CLI and no Compose v2 plugin.** The devcontainer had been getting
  both from its `docker-in-docker` feature, so four tasks worked there and would
  have failed in any other container of the same image.
- **No Buildx plugin,** which is not the cosmetic omission it looks like.
  Without it `docker build` falls back to the legacy builder, which shares no
  cache with the daemon's BuildKit — so `root:sandbox-image` recompiled
  Erlang/OTP from source. Observed, not predicted: the first `e2e:test` run
  inside the image printed `DEPRECATED: The legacy builder is deprecated` and
  then sat in `root:sandbox-image` for a minute before it was killed.

  The other half of that fallback turns out to be *safe*, and only because of
  this stage's other change. Only BuildKit reads a
  `<Dockerfile>.dockerignore`, so the legacy builder falls through to the
  context root's `.dockerignore` — which this stage made a deny-all. Measured
  with the plugin masked: `server:image` sends **9.728 kB** and fails at step
  10 with `COPY failed: file not found in build context or excluded by
  .dockerignore: stat timeline`. Loud, not a 1.1 GB context, and not silently
  wrong. Before the root `.dockerignore` existed it would have shipped the
  whole workspace.

  The three image tasks now name `docker buildx build` rather than
  `docker build`, so a missing plugin is an error instead of a deprecation
  warning followed by a slow, differently-behaving build.
- **No Python 3.** Debian's slim base ships no interpreter, and `root:test`
  runs `test-paths.py`, every Elixir app's `mix test.changed` calls it to select
  tests, and two shell scripts parse `moon query` output with it. This one hid
  behind a Moon cache hit on the first attempt.
- **`$PROTO_HOME/shims` was not on `PATH`,** and `pnpm` exists only there. Every
  `toolchain: "node"` task shells out through `bash -l`, which Debian's
  `/etc/profile` resets, so the shims directory has to come from
  `/etc/profile.d/proto.sh` and not from Moon's injected environment.
- **No hex and no rebar.** The first `mix deps.get` in a fresh container prompts
  to install hex, reads EOF from a non-interactive stdin, and fails.

That list is the argument for the decision, not a footnote to it. Four of the
five were latent bugs in the *devcontainer* story too — "works on my machine"
one layer down — and none would have been found by any CI shape that did not
run a plain container of this image.

## Alternatives considered

**The job runs inside the image via `container:`.** The socket is mounted, so
this is closer to working than expected — but two failures are structural, not
configuration:

- *Bind mounts resolve on the wrong side.* Compose runs in the job container and
  computes `/__w/<repo>/<repo>/e2e/bootstrap.exs`; the daemon runs on the host
  and finds no such path. The standard mitigation is to mount the workspace at
  an identical absolute path — which is exactly what this ADR chose, except
  that under `container:` the runner picks the container path (`/__w`) and the
  workflow would have to hardcode the host side (`/home/runner/work`) to match
  it. That is a bet on two undocumented runner internals.
- *The published port is not reachable.* The runner puts the job container on a
  network it creates and passes `--network` itself, so `web`'s host-published
  port is not on the job container's loopback and `--network host` is not ours
  to set.

Also: the image's `USER vscode` is uid 1000 and the runner's checkout is uid
1001, so `options: --user` would be needed anyway.

**Docker-in-Docker, a nested privileged daemon.** The nested daemon starts with
an empty image store *and an empty layer cache*, so `root:sandbox-image`
compiles Erlang/OTP from source on every CI run. PLAN.md's "Adding OS packages
after the fact" discipline exists precisely to keep that from happening; a CI
shape that forces it on every run defeats the discipline it is meant to
protect. It becomes workable only with a registry, or `docker save`/`docker
load` through the job cache — machinery this repository does not need, because
the chosen shape has one daemon and one layer cache.

**Running `moon ci` on the runner with proto instead of the image.** Cheapest,
and it discards the property the sandbox exists for. Rejected.

## Consequences accepted

- **A cold run is disk-hungry, and the workflow's prune step is a guess.**
  Measured while running the gate in the image: the container's cache root
  reached 7.2 GB (Cargo registry, the debug build of the plugin's test
  dependencies — wasmtime and aws-lc-sys — hex, Playwright, the Android SDK,
  Gradle), the host's own Cargo target directory 5.8 GB, and a 20 GB
  filesystem could not hold both. Two runs failed outright with
  `No space left on device` before the caches were pruned. A hosted runner
  starts with roughly 25–30 GB free and has to fit that cache root, the 4.6 GB
  sandbox image, the release image, and the BuildKit cache for the OTP build.
  "Free disk space" removes the preinstalled Android, .NET and Haskell trees to
  make room; whether that is enough is the single most likely first failure.
- **A cold CI run compiles Erlang/OTP from source.** An ephemeral runner has no
  Docker layer cache, and nothing here restores one, so the "Build the sandbox
  image" step pays the full cost on every run. The fix is a registry-cached
  image: `root:sandbox-image` already reads `SANDBOX_IMAGE`, and
  `run-in-sandbox.sh` passes it through, so pulling
  `ghcr.io/<owner>/baalbek-sandbox` and tagging it locally is a change to the
  workflow alone. It is deliberately not done here, because it means publishing
  a package, which is the repository owner's decision and not a build one.
- **Every build must use the default `docker` driver, never a
  `docker-container` builder.** The workflow's image build and `moon ci`'s later
  `root:sandbox-image` have to share one BuildKit cache, or the second one
  recompiles OTP. The `docker` driver is the daemon's own BuildKit, so they do;
  a `docker-container` builder with `--load` would import the final image and
  leave the daemon's cache cold. Measured: after the new apt layer was appended,
  a rebuild took 22 seconds with `RUN proto install` reported `CACHED`, and
  `root:sandbox-image` run from inside the container took 189 ms.
- **Image parity is per-step, not per-job.** `actions/checkout`,
  `actions/cache` and the artifact uploads run on the runner, with the runner's
  own tools. That is correct — they are not workspace tasks — but it does mean
  the job is not wholly inside the image, only every Moon task is.
- **The checkout is chowned to uid 1000.** Later runner-side steps can still
  read it, which is all the artifact uploads need, but a step that wanted to
  *write* to the workspace as the runner user would have to chown it back.
- **`--network host` is a Linux-runner assumption.** On Docker Desktop for
  macOS the same flag does not share the Mac's network namespace, so
  `run-in-sandbox.sh` is a CI and Linux-devcontainer tool, not the way a
  developer on a Mac runs tasks. They run `moon` directly in the devcontainer.
- **`mobile:build-ios` never runs in CI**, and is now *reported* rather than
  merely absent: `.github/scripts/report-excluded-tasks.sh` prints every task
  with `runInCI: false` alongside the tags that say why, and fails when an
  excluded task carries no tag at all. `moon ci` respecting `runInCI` was the
  mechanism; a silent exclusion was the risk.

- **`mobile:build-android` cannot run in this image on an aarch64 host,** so a
  full `moon ci` inside the image cannot reach green on ARM at all.
  `mobile/scripts/setup-android-sdk.sh` needs `sudo`, `qemu-user` and amd64
  multiarch packages there, because aapt2 has no aarch64 build; the image has
  none of the three, and the script says so and exits rather than skipping —
  which satisfies "never silently skipped" but is still a failed gate. On an
  x86_64 runner that whole branch is unreachable, as is the proxy-CA branch
  that is the script's only other `sudo`. So the task is expected to work in CI
  and is knowingly unrunnable in an aarch64 container.
- **The committed WASM plugin has to be byte-reproducible,** because
  `moon-elixir-plugin:build` compares a fresh build against it. A release build
  bakes `$CARGO_HOME`-relative `panic!` locations into the artifact as data, and
  `$CARGO_HOME` follows `$HOME`, so before this stage the artifact was
  reproducible only on the machine that last committed it — meaning that task
  would have failed on every GitHub run, and on every contributor's. It is
  `--remap-path-prefix` in `moon-elixir-plugin/scripts/build.sh` that makes the
  comparison mean anything. The general shape is worth remembering: a committed
  build artifact plus a reproducibility check is only as portable as the
  compiler's path handling.

## What is not verified

No part of the GitHub-specific half of this has run on GitHub. What was checked
locally, in this sandbox, against a real Docker daemon and the real workspace:

- `moon run e2e:test` through `run-in-sandbox.sh` — the hardest single case.
  It rebuilt `root:sandbox-image`, `server:image` and `web:image` from inside
  the container, brought the compose stack up with its bind-mounted
  `bootstrap.exs` resolving on the host, reached the published port at
  `http://localhost:4014`, and passed all six Playwright tests. That exercises
  the socket mount, the identical-path mount, the shared network namespace and
  the new Chromium libraries in one run.
- Postgres over `--network host`: `pg_isready -h localhost -p 5432` from inside
  the container reaches a Postgres published on the host. That is the mechanism
  the workflow's `services:` block relies on, though not that block itself.
- Python 3, hex, rebar, `pnpm` on `PATH`, `docker buildx` and `docker compose`,
  each run in a fresh container of the image.
- Byte-identical WASM from two different `$HOME`s and two separate registry
  downloads: `sha256 974fad1d…`, host and container.
- The legacy-builder fallback, with the Buildx plugin masked: a 9.728 kB
  context and a failed `COPY`, not a silent 1.1 GB one.
- `actionlint` accepts `.github/workflows/ci.yml`, which proves its syntax, its
  expressions and its shell fragments — and nothing about whether the runner
  behaves as the source quoted above says it does.

Unverified until the workflow runs on GitHub: the `services:` Postgres itself;
the `MOON_BASE` resolution for each event type; whether a hosted runner has the
disk and the wall-clock budget for a cold run; the `chown` interaction with
`actions/cache`'s and `actions/upload-artifact`'s post-steps; and
`mobile:build-android` on x86_64, which has never run outside an aarch64 host
here.

One thing the cold run in the image did find, and this ADR is not the place to
fix: on a cold `~/.cache/gleam`, one of the three `timeline:*` tasks
intermittently fails resolving Gleam dependencies with
`error sending request for url (https://hex.pm/api/packages/…)`. Two cold runs,
two hits, different tasks and different packages each time; an immediate re-run
of the same task passes. It never appeared on the host, where that cache has
been warm since Stage 5, so CI's first run is where it will show. The
mechanism is not established — the obvious concurrency theory does not fit,
because one hit was on a task that runs strictly after another that had already
succeeded — so nothing was changed for it here rather than adding a retry that
would hide it.

Two things this decision leans on that nothing checks:

- **The devcontainer's feature-entrypoint composition.** `devcontainers/cli`
  generates an override that runs each feature's entrypoint and then
  `exec "$@"` with the compose `entrypoint` and `command` as its arguments,
  which is what lets `.devcontainer/entrypoint.sh` chown the named volumes
  while docker-in-docker still starts its daemon. That was read from the CLI's
  source, not observed. If it ever replaced rather than wrapped the entrypoint,
  every volume would stay root-owned and nothing would say so.
- **The chown in that entrypoint filters on the `/workspaces/` prefix,** so it
  does not see the `moon-cache` volume whenever `.moon/cache` is a symlink off
  the tree: Docker resolves the link and mounts the volume at the target
  instead. Harmless where the target is already writable, silent where it is
  not.

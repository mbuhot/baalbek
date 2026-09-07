# baalbek

A mixed-language modular monolith — Elixir, Rust, Gleam, TypeScript — built as
one Moon workspace, with enforced module boundaries, change-aware test
selection, and architecture documentation generated from the workspace itself.

It is Alembic's reference project for consolidating a microservice estate: the
end state of that playbook, in code, at a size one person can read. The domain
is field service dispatch — jobs, technicians, work orders, invoices — chosen
because it needs several genuinely different components rather than because
anyone needs another dispatch system.

The point of the repository is the *shape*, not the features:

- Every component keeps its native toolchain. ElixirLS, rust-analyzer and the
  TypeScript language server all see ordinary projects, because Moon does not
  own compilation — it owns the project graph, the task graph, caching and
  affected-detection.
- Every cross-component edge is a **build** edge, including the ones that would
  normally be runtime-only. The PWA depends on a client generated from the
  server's OpenAPI document, so a breaking API change fails the consumer's
  build instead of surfacing in production.
- Every component's specification lives with the component, in its own `spec/`
  directory: Gherkin acceptance criteria, dated UI mock snapshots, ADRs.

`seed.md` is the specification this was built from, written as a decision
record. `PLAN.md` is the stage-by-stage build plan and the decisions taken
while building. Neither is a summary of the other, and this file is not a
summary of either.

## Getting a working environment

Every language toolchain is pinned in `.prototools` and installed by
[proto](https://moonrepo.dev/proto) — Erlang, Elixir, Gleam, Rust, Node, pnpm,
a JDK, and Moon itself. No language toolchain comes from apt, from brew, or
from a host asdf. What the container image does install is OS-level and
deliberate: the build dependencies Erlang-from-source and Rustler need, a
Postgres client, a Docker client, Python 3, and the shared libraries
Playwright's Chromium links against. The Android SDK is the same category,
downloaded on first use.

### The devcontainer (recommended)

Open the repository in VS Code and run **Dev Containers: Reopen in Container**.
`.devcontainer/` builds the root `Dockerfile` and adds Postgres 17 as a compose
service. The image already ran `proto install`, so the Erlang-from-source build
is a cached layer rather than your first half hour.

Build-artifact directories — `_build`, `deps`, `node_modules`, `target`, each
project's `build/`, and `.moon/cache` — are **named Docker volumes**, not part
of the bind-mounted source tree. That is a correctness measure, not a
performance one; see "Working-tree hazards" below.

### Natively

```bash
proto install          # every tool in .prototools
moon --version
docker compose -f .devcontainer/docker-compose.yml up -d postgres
```

You then also need a Docker daemon (four tasks build images and `e2e:test`
composes a stack), the Android SDK for `mobile:build-android` — bootstrapped by
`mobile/scripts/setup-android-sdk.sh` — and Chromium's OS libraries for
`e2e:test`. macOS additionally gets `mobile:build-ios`, which cannot run
anywhere else.

## What is in here

| Project | Language | Owns | Notes |
|---|---|---|---|
| `core` | Elixir / Ash | schema `core` | Jobs, customers, sites, work orders. Publishes OpenAPI. |
| `identity` | Elixir / Ash | schema `identity` | Technicians, dispatchers, authentication. |
| `billing` | Elixir / Ash | schema `billing` | Invoices raised from completed jobs. |
| `timeline` | Gleam | schema `timeline` | Event-sourced shift/travel/on-site log; availability projections. |
| `timeline_facade` | Elixir | — | Sole caller of the Gleam modules, enforced by `boundary`. |
| `pricing` | Rust crate | — | Quote computation: travel, labour, parts. |
| `pricing_native` | Elixir | — | Rustler NIF facade; sole referencer of the NIF module. |
| `server` | Elixir / Phoenix | — | HTTP surface, OpenAPI, and the `MIX_ENV=prod` release. |
| `web` | TypeScript | — | PWA: dispatch board and technician view. |
| `core-api-client` | TypeScript | — | Generated from `core`'s OpenAPI document. |
| `mobile` | Capacitor | — | Android (Gradle) and iOS (xcodebuild) wrappers over the PWA. |
| `e2e` | Playwright | — | Drives the composed release stack, never a dev server. |
| `explorer` | TypeScript | — | Static site generated from the project graph, git history and `capabilities.yml`. |
| `moon-elixir-plugin` | Rust → WASM | — | Infers `dependsOn` from `mix.exs` path dependencies. |
| `root` | — | — | Repo-wide tooling: the test-path convention check and the sandbox image build. |

### Why it is shaped this way

Four decisions do most of the work. Each has an ADR; this is only the index.

**Poncho, not umbrella.** Each Elixir component is a standalone Mix project
with path dependencies on its siblings. Path deps make the dependency direction
explicit and fail on cycles, and each app owns its own `test/`, so
component-level test selection falls out of the layout instead of being
configured.

**One Postgres, one schema and one role per component.** Each Elixir component
has its own Ecto Repo connecting as its own role, granted only on its own
schema. A cross-boundary query is a permissions error, not a code-review
finding.

**Two languages sit outside Mix, behind facades.** `pricing` (Rust) and
`timeline` (Gleam) each have a thin Elixir facade app, and `boundary` enforces
that nothing else reaches past it. The cross-language edge is declared in
`moon.yml`, which is what makes a Rust or Gleam change invalidate the Elixir
suites — no native test-impact tool can see across that boundary.

**A cross-project edge is a task dependency on an output-declaring task**, never
another project's files as `inputs`. Moon folds an upstream task's *hash* into
its dependents' only when that task declares `outputs`, and that composes
transitively; a `project://` input does not.
`spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md` has the
measurements and the three defects that produced the rule.

## Running things

```bash
moon run core:test                 # one project's suite
moon run :test                     # every project's suite
moon ci                            # everything affected, the way CI runs it
moon check --all                   # a deliberate full sweep
```

The three gates are not interchangeable, and reaching for the widest one is a
mistake this repository has already made:

- **A project's own gate** (`moon run <project>:test`) proves that project does
  what it claims. It is the fast loop.
- **`moon ci`** proves nothing else regressed. It diffs against a base ref,
  maps changed files to owning projects, walks the graph to include dependents,
  and runs only the affected tasks — continuing past the first failure, and
  honouring `runInCI`, so the macOS-only iOS build drops out without a special
  case. It is what CI actually runs, which makes it the honest predictor.
- **`moon check --all`** runs every build and test task unconditionally. It
  ignores `runInCI`, has no affected-detection, and as the workspace grew it
  came to demand a Docker daemon, a free port, browser binaries and OS
  libraries all at once to answer "does this still hang together". Use it for a
  deliberate full sweep — after changing how the project graph is inferred, say
  — not as a reflex.

Some useful specifics:

```bash
moon run e2e:test -- --grep @capability/dispatch-board  # one capability's journeys
moon run explorer:build                                # the explorer, into explorer/dist
moon run mobile:build-android --force                   # pick up a changed MOBILE_API_BASE_URL
```

Tasks that build Docker images are uncached on purpose: an image in the local
daemon is not a file output, so a Moon cache hit would replay a log claiming
the image was built after `docker image prune` removed it. They therefore need
no `--force`. What does need it is a task whose behaviour depends on a variable
that is deliberately not in its hash, like `mobile:build-android` and
`MOBILE_API_BASE_URL`.

## CI

`.github/workflows/ci.yml` runs `moon ci` **inside this repository's own
sandbox image** — the same image the devcontainer builds. That is the point: a
GitHub-hosted runner ships Node, Python, a JDK and gcc, so a task that forgot
to declare an input would find its tool anyway and pass. Moon's task cache is
deliberately not restored between runs for the same reason.

The job runs on the runner and invokes the image per step, via
`.github/scripts/run-in-sandbox.sh`, rather than using `container:` or a nested
daemon. Both alternatives break on this workspace in specific ways — bind
mounts that resolve on the wrong side of the socket, a published port that is
not on the job container's loopback, an empty nested layer cache that
recompiles Erlang every run. The reasoning, and the runner internals it rests
on, are in
`spec/decisions/adr-0007-ci-runs-moon-ci-inside-the-sandbox-image.md`.

The same script reproduces a CI failure locally, on Linux:

```bash
.github/scripts/run-in-sandbox.sh moon ci
```

It gives the container its own Moon cache, so the run genuinely re-does the
work rather than replaying hits the host produced. Two caveats:

- It does **not** give the container a clean checkout. A build already run on
  the host leaves output in the tree, some of it symlinked into the host's
  `$HOME`, which dangles inside the container. The script warns when it finds
  such a link, and CI never hits it because a fresh checkout has no build
  trees — but a local run is only as faithful as the tree it starts from.
- On an **aarch64** host it cannot reach green, because
  `mobile:build-android` needs `qemu-user` and `sudo` there (aapt2 ships no
  aarch64 build) and the image has neither. It fails loudly and by name, which
  is the intended behaviour, but it means an Apple Silicon machine can run
  every other task in the image and not that one.

`.github/scripts/report-excluded-tasks.sh` names every task `moon ci` will not
run and the tag that says why, and fails if an excluded task carries no such
tag. An exclusion nobody can read is how a suite quietly stops being run.

## Where the reasoning lives

| Where | What |
|---|---|
| `seed.md` | The specification, as a decision record: the architecture, the testing strategy, what is deliberately out of scope. |
| `PLAN.md` | The build plan, the stage gates, and the decisions taken during the build. |
| `CLAUDE.md` | Conventions for anyone — human or agent — editing the repository. |
| `spec/decisions/` | Workspace-wide ADRs. `spec/decisions/README.md` states the numbering and immutability rules. |
| `<component>/spec/decisions/` | Decisions confined to one component. |
| `<component>/spec/features/` | Gherkin acceptance criteria, executed by ExUnit. |
| `web/spec/mocks/` | Dated UI mock snapshots: intent at build time, never maintained truth. |
| `<component>/README.md` | What the component is, and how to run it. |

ADRs are immutable. A decision that no longer holds gets a new ADR that
supersedes it; the old one is marked and neither its reasoning nor its date is
edited. Several are already superseded, and following the chain is the point.

`explorer/capabilities.yml` is the one hand-maintained input to the
architecture explorer: **eleven** capabilities, each claimed by the components
that serve it (a `moon.yml` tag) and by the e2e journeys that prove it (a
Playwright tag). Eleven is the number that matters — seed.md §9 asks for "a
dozen capabilities, not hundreds", and that is checkable only if the count is
the business vocabulary and nothing else. The file's five `platform:` entries
are the other list: projects exempted from claiming a capability, each with its
reason. A claim naming a capability the vocabulary does not define fails the
build; a capability with no e2e coverage is reported, not failed.

## Working-tree hazards

On macOS and Windows the working tree usually sits on a case-insensitive
filesystem, reached from the Linux container over a bind mount. Two failure
modes follow, and both have bitten this repository repeatedly.

**`Foo` and `foo` are the same file.** The container can still show two
directory entries, because it caches one per spelling — sometimes with a stale
size, which makes one file look like two that differ. Deleting the apparent
duplicate destroys the real file. Reproduced deliberately: creating
`.CaseProbe`, looking up `.caseprobe` once, then `rm .caseprobe` deleted
`.CaseProbe`. Use each path's canonical spelling, never delete an apparent
case-duplicate, and trust `git ls-files` over `ls`.

**Concurrent writes to the bind mount can corrupt.** Observed on VirtioFS: a
source file silently zeroed under concurrent rewrites, `cp` producing a
NUL-filled file of the correct length, and Moon's own lock files failing
`ENOENT` immediately after being created. This is why the devcontainer puts
every build-artifact directory on a named volume, why `CARGO_TARGET_DIR`,
Gradle's build directory and Playwright's output directory are all redirected
to `~/.cache`, and why `.moon/cache` must not live on the mount.

`CLAUDE.md` has the working rules for both.

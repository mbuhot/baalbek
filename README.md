# baalbek

baalbek is Alembic's reference project for a mixed-language modular monolith.
One [Moon](https://moonrepo.dev) workspace holds 17 projects in Elixir, Rust,
Gleam, TypeScript and Capacitor. The domain is field service dispatch: jobs,
technicians, work orders and invoices.

## What is in it

| Project | Language | Purpose |
|---|---|---|
| `core` | Elixir / Ash | Jobs, customers, sites and work orders. |
| `identity` | Elixir / Ash | Technicians, dispatchers and authentication. |
| `billing` | Elixir / Ash | Invoices for completed jobs. |
| `timeline` | Gleam | An event-sourced shift log, and the availability it projects. |
| `timeline_facade` | Elixir | The only caller of the Gleam modules. |
| `pricing` | Rust | Quote computation: travel, labour and parts. |
| `pricing_native` | Elixir | The Rustler NIF facade. |
| `server` | Elixir / Phoenix | The HTTP surface, the OpenAPI document and the `MIX_ENV=prod` release. |
| `web` | TypeScript | The PWA: a dispatch board and a technician view. |
| `core-api-client` | TypeScript | The client generated from the OpenAPI document. |
| `mobile` | Capacitor | The Android and iOS wrappers over the PWA. |
| `e2e` | Playwright | Drives the composed release stack. |
| `explorer` | TypeScript | The architecture site generated from the project graph. |
| `moon-elixir-plugin` | Rust to WASM | Infers `dependsOn` from `mix.exs` path dependencies. |

Three more projects serve no business capability. `root` owns the repo-wide
checks and the sandbox image build. `config` holds the shared TypeScript
settings. `spec` holds the workspace ADRs.

Each project keeps its native toolchain. `.prototools` pins every tool version,
and [proto](https://moonrepo.dev/proto) installs them. Erlang builds from
source.

## How to run it

```bash
proto install                # install every tool in .prototools
moon run core:test           # one project's suite
moon ci                      # every affected task, the way CI runs it
moon run e2e:test            # Playwright against the release stack
```

For a ready environment, open the repository in VS Code and run **Dev
Containers: Reopen in Container**. `.devcontainer/` builds the sandbox image and
adds Postgres 17. The image already ran `proto install`, so the Erlang build is
a cached layer.

Three gates do different work. `moon run <project>:test` proves one project.
`moon ci` proves that nothing else regressed. `moon check --all` is a deliberate
full sweep, and it needs a Docker daemon, a free port and browser libraries at
once.

## The properties it demonstrates

| Property | Where to look |
|---|---|
| A module boundary is compiler-enforced inside and across the Elixir apps. `ash_boundary` derives the public surface from the Ash domain. | `spec/decisions/adr-0001-ash-boundary-for-ash-domains.md` |
| A Rust or Gleam change invalidates the Elixir test suites. Each cross-language edge is a declared task dependency. | `pricing_native/moon.yml`, `timeline_facade/moon.yml` |
| A task dependency changes a dependent's hash only when the upstream task declares `outputs`. The rule replaced `project://` inputs after three defects. | `spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md` |
| A breaking API change fails the consumer's build. The PWA depends on a client generated from the `server:openapi` output. | `core-api-client/moon.yml` |
| Each Elixir component connects as its own Postgres role, granted only on its own schema. | `core/priv/repo/bootstrap.sql` |
| The e2e suite drives a containerised `MIX_ENV=prod` release, never a development server. | `e2e/moon.yml`, `e2e/docker-compose.yml` |
| The architecture site regenerates from `moon project-graph --json`, git history and 11 named capabilities. | `explorer/moon.yml`, `explorer/capabilities.yml` |
| Within an Elixir app, `mix test --stale` selects what to rerun locally. | `spec/decisions/adr-0012-*` |

## CI

GitHub Actions runs `moon ci` inside this repository's own sandbox image. A
hosted runner ships Node, Python, a JDK and gcc, so a task with an undeclared
input would pass there. `main` runs cold and writes Moon's task cache; a pull
request restores it and never writes it, so a pull request can only replay what
a cold `main` run built.

| Measure | Value |
|---|---|
| A full-graph `moon ci` run, in the image | 24 minutes 26 seconds |
| The same run, on a bare runner | 22 minutes 6 seconds |
| The image step, against the GHCR layer cache | 62 seconds |
| The image step, with no cache | 2 minutes 48 seconds |
| `e2e:test` in CI | About 53 seconds |

The cached image step does not recompile Erlang.
`spec/decisions/adr-0007-ci-runs-moon-ci-inside-the-sandbox-image.md` and
`spec/decisions/adr-0008-the-sandbox-image-is-published-to-ghcr.md` record why.

One exception is accepted. An iOS build needs macOS, so `mobile:build-ios`
carries the `requires-macos` tag, sets `runInCI: false`, and logs a skip
elsewhere.

## Working-tree hazards

The working tree carries source and nothing else. Every directory the build
writes into sits on local storage at its usual in-tree path — a named volume in
the devcontainer, and `scripts/mount-build-dirs.sh setup` anywhere else, which
bind-mounts them and needs running again after a reboot.
`spec/decisions/adr-0013-build-output-lives-off-the-working-tree.md` says why
the paths cannot simply move.

On macOS and Windows the working tree usually sits on a case-insensitive
filesystem. `Foo` and `foo` are then one file, and a listing can still show two
entries. Never delete an apparent case-duplicate. `CLAUDE.md` holds the working
rules.

## Where the reasoning is

`seed.md` is the specification, written as a decision record. `PLAN.md` is the
stage-by-stage build plan and the decisions taken during the build.
`spec/decisions/` holds the workspace ADRs, and each component holds its own
under `<component>/spec/`. An ADR is immutable: a new ADR supersedes an old one,
and the old text stays as written.

# ADR-0001: Release assembly, and how Gleam code gets into the release

**Status:** Accepted. Amended by spec/decisions/adr-0010: `timeline_facade`
names the shipment's applications itself rather than listing the directory,
and the task that builds the shipment is `timeline:build`.
**Date:** 2026-09-06
**Stage:** 6c

Supersedes `timeline_facade/spec/decisions/adr-0001-gleam-elixir-interop.md`.
That ADR's *loading mechanism* is replaced; the rest of its findings still
hold — see "What ADR-0001 got right and this does not change" below.

**Context:** PLAN.md gives `server` two jobs — "Release assembly; HTTP
surface" — and Stage 6 shipped only the second. PLAN.md's Stage 6c section
states the specific defect this closes: `timeline_facade/mix.exs` loaded
`timeline`'s compiled Gleam output with `Code.prepend_path/1` at the top
level of `mix.exs`. A release has no `mix.exs` and never evaluates it, and
`timeline`'s output lived in `timeline/build/dev/erlang/*/ebin`, a directory
`mix release` has no reason to traverse. A release would therefore not merely
fail to prepend a path — it would not contain the Gleam code at all.

## Decision

### `timeline` is packaged as real OTP applications, not a code path

`timeline/scripts/package-otp.sh` (Moon task `timeline:package`) produces
`timeline/build/otp/<app>/ebin/...` — one ordinary OTP application directory
per application in `timeline`'s runtime closure: `timeline` itself, its Gleam
dependencies (`gleam_stdlib`, `gleam_erlang`, `gleam_otp`, `gleam_time`,
`pog`, `exception`) and `pog`'s Erlang-native transitive dependencies
(`pgo`, `pg_types`, `backoff`, `opentelemetry_api`).

`timeline_facade/mix.exs` then declares **one Mix path dependency per
directory**, each with `compile: "true"` — the shell no-op, because the
directories are already compiled.

That is the whole mechanism, and every property that matters follows from it:

- Mix links each dependency's `ebin/` into `_build/<env>/lib/<app>/`, so
  `:timeline` and friends are ordinary Mix dependencies from that point on.
- Because they are Mix dependencies of `timeline_facade`, and `server` takes
  a path dependency on `timeline_facade`, they appear in
  `timeline_facade.app`'s `applications` list, and therefore in the
  application tree `mix release` walks. `mix release` copies them into
  `lib/timeline-0.1.0/` etc. like any Hex dependency.
- `prune_code_paths: false` is gone. It existed only to stop Mix pruning a
  path Mix was never told about; Mix is now told about it.
- `mix.exs` still reads the filesystem, but it reads it to *declare
  dependencies*, and it does so at assembly time. The release itself
  contains no reference to `mix.exs`, to `timeline/`, or to any host path.

### The build output must come from `gleam export erlang-shipment`

`gleam build`'s dev output writes `{modules, []}` into every `.app` file it
generates — ADR-0001's observation, re-verified in this stage. `gleam export
erlang-shipment` writes the real module list.

This is not cosmetic, and it is the part that is easy to get wrong, because
`{modules, []}` costs nothing in dev and breaks only in a release:

- `mix release` generates the boot script (`releases/<vsn>/start.script`)
  from each application's `.app` `modules` list.
- An Elixir release runs the VM in **embedded** code-loading mode
  (`:code.get_mode() == :embedded`, confirmed in the built release). Embedded
  mode loads what the boot script names and does not search the code path on
  a missing module the way interactive mode does.
- So a release built from a `{modules, []}` application ships the `.beam`
  files — they are physically in `lib/timeline-0.1.0/ebin/` — and still
  answers `function :timeline.current_availability/1 is undefined (module
  :timeline is not available)`. Reproduced deliberately in this stage.

`scripts/otp-closure.escript` therefore **aborts** on any application whose
`.app` declares no modules, rather than repairing it: a silently-repaired
`.app` would hide a change in how `timeline` is built.

One trap for anyone re-checking this: `bin/server eval` runs its own VM in
**interactive** mode, not embedded. A `{modules, []}` release answers an
`eval`'d `:timeline.current_availability/1` correctly, because interactive
mode falls back to searching the code path. The failure only appears under
`start` (and therefore `rpc`, which attaches to the started node). Use those.

Two consequences worth recording:

- The shipment export also fixes `Application.get_application(:timeline)`,
  which ADR-0001 recorded as broken. OTP's module→application reverse lookup
  is built from the same `modules` list.
- The export copies dev-only packages too (`gleeunit`, and the
  Elixir-target packages it drags in). `otp-closure.escript` walks the
  `applications` keys from `timeline` outward and keeps only what is
  reachable, skipping applications Erlang/OTP provides and the ones Elixir
  itself provides (`elixir`, `eex`, `logger`, `mix`, ...) — `opentelemetry_api`
  genuinely declares `elixir` as a dependency, and vendoring a second copy of
  Elixir into an Elixir release would be wrong.

### `server` gets a real `mix release` and runtime-only configuration

`releases: [server: [include_executables_for: [:unix], applications: [server:
:permanent]]]`, plus `server/Dockerfile`: a two-stage build whose build stage
is this repository's own sandbox/CI image, so the release is compiled by the
exact proto-pinned toolchain every other task uses, and whose runtime stage
carries only the release (which embeds ERTS) and the shared libraries ERTS
and the Rustler NIF link against.

All connection settings, the HTTP port and `secret_key_base` moved from
`config/config.exs` to `config/runtime.exs`, which a release evaluates at
boot. `config.exs` keeps only what is genuinely compile-time (`:mime`
extensions, `ecto_repos`, `ash_domains`, the `:ash` flags, the endpoint
adapter). `SECRET_KEY_BASE` has no default in `:prod` and raises if unset.

`server/config/config.exs`'s duplication of the domain apps' Repo settings —
flagged as a wart in Stage 6a's review — is reduced, not removed. It is
inherent to the poncho layout: Mix path dependencies do not load their own
config, so the top-level project must declare it. What moved is *where*: one
`pg.(prefix, role, pool_size)` closure in `runtime.exs` now covers all three
Repos instead of three hand-copied blocks.

`timeline` is the exception: it is not an Elixir application and reads
`TIMELINE_PG_HOST` / `TIMELINE_PG_PORT` / `TIMELINE_PG_DATABASE` /
`TIMELINE_PG_PASSWORD` from the OS environment itself, through a small Erlang
FFI module (`timeline/src/timeline_ffi.erl`). ADR-0001 recorded the hardcoded
connection as a deliberate simplification with an additive fix; this is that
fix, and it was needed here because the release image must reach a Postgres
that is not on `localhost`.

### The gate is an HTTP route, not a remote console

`GET /api/timeline/technicians/:id/availability` and `POST
/api/timeline/technicians/:id/events` are served by `ServerWeb.TimelineRouter`
through `Server.Timeline`, which calls `TimelineFacade`. Two reasons for a
route over `bin/server rpc`:

- Stage 9's e2e suite needs an endpoint it can hit, which converts this
  stage's one-time check into a standing one (PLAN.md Stage 9 says exactly
  this).
- It keeps `boundary`'s layering honest: `ServerWeb` may only reach `Server`'s
  exports, so the call into `TimelineFacade` has to sit in `Server.Timeline`.

Plain JSON, not JSON:API: `timeline` is an event-sourced Gleam package, not
an Ash resource, so `ash_json_api` has nothing to generate from. The response
borrows JSON:API's `data`/`type`/`attributes` shape so a client sees one
idiom, without claiming the content type.

## Alternatives considered

### Keep `Code.prepend_path/1` and teach the release about it

A release *can* be given extra code paths — `RELEASE_BOOT_SCRIPT`, a custom
`rel/env.sh`, `-pa` in `vm.args`. All of them fail for the same two reasons:
the `.beam` files still would not be *inside* the release (the image would
have to ship `timeline/build/` separately and keep it in sync), and embedded
mode would still not load them without a boot script entry. This is the
option PLAN.md explicitly rules out ("Do not just make the existing
`Code.prepend_path` hack work harder"), and the mechanics agree.

### Ship the `gleam export erlang-shipment` tree beside the release

The shipment includes `entrypoint.sh` and can be run directly by Erlang. It
is the right artifact for deploying a *Gleam* application; it is the wrong
one here, because the process that must load these modules is `server`'s
release, and two independently-assembled BEAM trees in one image means two
copies of every shared dependency and no single boot script. The shipment is
used as an *input* to packaging rather than as a deployment artifact.

### Rewrite the `{modules, []}` list ourselves from `gleam build` output

`otp-closure.escript` could fill in the module list by listing `*.beam`. That
would work today and would remove the dependency on `gleam export`. Rejected:
it makes this repo responsible for a fact Gleam already states correctly, and
it would silently keep working if a future Gleam release changed what belongs
in an application. Asserting is cheaper to maintain than repairing.

### `mix_gleam`, and a plain Mix `path:` dependency on `timeline/`

Both were considered and rejected in ADR-0001, for reasons this stage does
not change. Worth noting that the second one now *almost* works: the reason
it failed was the absence of a manifest file at the path dependency's target,
and `compile: "true"` is precisely the escape hatch Mix's own error message
points at ("pass `:compile` as an option to customize compilation"). It still
would not work against `timeline/` itself, which has no `ebin/`; it works
against the packaged output, which is what is done here.

## Rough edges / known limitations

- **`timeline_facade`'s dependency list is computed from a directory
  listing.** `mix.exs` calls `File.ls/1` on `../timeline/build/otp`. If that
  directory is missing, `mix.exs` raises with an instruction to run
  `moon run timeline:package`; if it is *stale*, Mix will happily use the
  stale contents. The Moon graph is what keeps it fresh (`timeline:package`
  is a task-level `deps` entry of `timeline_facade:test`, `server:test`,
  `server:openapi` and `server:release`), so a build that bypasses Moon can
  still get a stale answer.
- **All eleven path deps carry `override: true`.** They are generated from a
  directory listing, so the flag cannot be applied selectively without
  hand-maintaining an exception list. The consequence is that the
  Gleam-vendored copies of `opentelemetry_api`, `backoff` and `pg_types`
  would silently win over a Hex dependency of the same name that some future
  `server` dependency pulls in — no collision exists today, but
  `opentelemetry_api` is a realistic one. The symptom would be a version
  mismatch, not a missing module.
- **`server:release` writes to `/.artifacts/server-release` and declares no
  `outputs`.** The release is 101 MB (it embeds ERTS). Keeping it under
  `server/` made Moon walk and hash it for anything holding a
  `project://server` input at the same moment `--overwrite` was deleting it,
  which failed runs outright; and a declared output cost a 37.7 MB archive
  per cache miss for an artifact nothing consumes, since `server:image`
  compiles its own release inside the Docker build stage. If a future
  consumer needs the tree as an artifact, declare the output then — and note
  that `include_erts: false` would shrink it, at the cost of a runtime image
  that must supply a matching ERTS.
- **`project://` inputs are deliberately absent for `timeline`.** The
  cross-language edge is declared as source globs (`/timeline/src/**/*` and
  friends) instead, for the same reason: `timeline:package` rewrites
  `timeline/build/` while other tasks may be hashing it. `hasher.ignorePatterns`
  in `.moon/workspace.yml` keeps build output out of every task hash, but it
  does not stop the directory walk, so both changes are needed.
- **`server:image` depends on `root:sandbox-image`, which Moon cannot cache.**
  A docker image in the local daemon is not a file output. Docker's own layer
  cache makes the repeat cost small, but `moon ci` will always re-run it.
- **The packaging script copies with `tar`, not `cp`.** `cp -R` across this
  repository's virtiofs mount was observed writing a NUL-filled file of the
  correct length in place of a `.app` file. The script re-runs
  `otp-closure.escript` against the copied tree afterwards, which is what
  catches that class of corruption rather than the copy method alone.
- **`boundary` still cannot enforce "sole caller of `:timeline`."** Making
  `:timeline` a real OTP application fixed `Application.get_application/1`,
  which ADR-0001 identified as one of two causes — but the other still holds:
  `boundary` filters candidate modules down to names beginning `Elixir.`, and
  Gleam's modules are bare atoms. The grep-based compensating check in
  `timeline_facade`'s test task remains the control. Amended by
  `timeline_facade/spec/decisions/adr-0002-the-gleam-boundary-grep-is-withdrawn.md`,
  which withdraws that check and leaves review as the only control.

## What ADR-0001 got right and this does not change

- `timeline` stays a standalone Gleam project with its own `gleam.toml`, built
  and tested by plain `gleam build` / `gleam test`, with no Mix involvement.
- Gleam functions are plain Erlang functions once compiled; there is no
  runtime bridge, marshalling layer or NIF.
- `rebar3` must be on `PATH` to build `timeline` at all, provisioned by
  `mix local.rebar`.
- The `pog` pool is memoized per role in `:persistent_term`, unlinked from its
  starting process, and still sits outside any supervision tree.
- `Application.ensure_all_started(:pgo)` in `db.gleam` is now redundant in a
  release — `:pgo` is a started application there — but is still required
  wherever `timeline` is loaded into a VM that does not start it.
- `gleam_stdlib` stays pinned below 1.0 until the Gleam proto pin moves past
  1.14.

## What was verified, concretely

- `MIX_ENV=prod mix release` produces a release tree containing
  `lib/timeline-0.1.0/ebin/*.beam` and the ten other Gleam-side applications.
- The release boots, serves `core`'s JSON:API (list and create round trip),
  and serves `/api/timeline/...`, returning a projection replayed from the
  event log by Gleam code — `{:ok, {:on_site, "site-42"}}` from inside the
  running release, with `:code.which(:timeline)` pointing into the release's
  own `lib/`.
- The same is true of the container built from `server/Dockerfile`, pointed at
  Postgres by environment variables alone.
- Negative, mechanism: a release built from the previous `mix.exs` contains
  `timeline_facade` and **no** `timeline`, `pog`, `pgo` or `gleam_*`
  application; `:code.which(:timeline)` is `:non_existing`.
- Negative, `{modules, []}`: a release built from an otherwise-identical tree
  with `timeline.app`'s module list emptied contains every `.beam` file and
  still fails with "module :timeline is not available".

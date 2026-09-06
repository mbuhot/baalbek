# e2e

**Language:** Playwright

**Purpose:** Depends on `server` + `web` builds.

Full run on main and nightly as the backstop; selection is a fast pre-merge
gate, never the final word. No deploy without the full e2e suite green.

## Stage 9 (this stage)

The suite drives a **containerised stack running the `MIX_ENV=prod` release**
— never `mix phx.server` (PLAN.md Stage 9). `docker-compose.yml` composes four
containers:

| Service | Image | Role |
|---|---|---|
| `postgres` | `postgres:17` | The stack's own database, `baalbek_e2e`, on tmpfs, no published port. |
| `bootstrap` | `baalbek-server:latest` | One-shot: roles, schemas, migrations, timeline tables. |
| `server` | `baalbek-server:latest` | The release, from `moon run server:image`. |
| `web` | `baalbek-web:latest` | The PWA, from `moon run web:image` — serves the built bundle, proxies `/api` to `server`. |

Both tiers run the image that ships; this file adds a database and a mounted
bootstrap script, nothing else. `global-setup.ts` brings the stack up, asserts
each container runs the image id its project built (not merely *something* on
that port), and waits for the API; `global-teardown.ts` destroys it and its
data.

- **Schemas come from inside the release.** A release has no Mix, so no
  `mix *.bootstrap` and no `mix ecto.migrate`. `bootstrap.exs` runs under
  `bin/server eval` and uses the bootstrap SQL, the Ecto migrations and
  `timeline`'s Gleam bootstrap module that all ship *in* the release.
- **One origin.** The PWA and the API share a host and port, so no CORS grant
  and no per-environment base URL are needed. `web/src/api.ts` defaults to the
  origin serving the app, and `web/Dockerfile` is what makes that true — the
  deployment topology is owned by `web`, not by this suite.
- **The Gleam-in-release check is standing, not one-off.**
  `tests/timeline.spec.ts` posts events and reads back the replayed
  availability projection through `/api/timeline/...`, which reaches Gleam code
  via `timeline_facade`. A release that stops bundling `timeline`'s BEAM files
  fails it.

Why the stack is composed this way, and what was rejected, is in
`spec/decisions/adr-0001-dockerized-e2e-stack.md`.

## Running it

```bash
moon run e2e:test          # builds the image and the PWA first, then runs
```

Locally, against a stack you keep between runs:

```bash
E2E_KEEP_STACK=1 pnpm --filter e2e exec playwright test
```

`E2E_BASE_URL` points the same suite at an environment someone else runs — when
it is set, the suite starts no containers, checks no image ids, and tears
nothing down; it only waits for that URL to answer. `E2E_HOST_PORT` (default
4014) moves the published port of the local stack; `SERVER_IMAGE` and
`WEB_IMAGE` select different images.

### Browser binaries and their OS libraries

`moon run e2e:test` runs `playwright install chromium`, which downloads ~115 MB
into `~/.cache/ms-playwright`. The **shared libraries** that browser links
against (`libglib-2.0`, `libnss3`, …) are OS packages, and the sandbox/CI
image (root `Dockerfile`) does not carry them yet. On a machine without them
Chromium fails to launch with `error while loading shared libraries`. Install
them with:

```bash
cd e2e && sudo -E env PATH="$PATH" pnpm exec playwright install-deps chromium
```

Stage 12 (CI) has to add that package set to the sandbox image; it is left out
here deliberately, because editing the root `Dockerfile` invalidates the
sandbox image layer that builds Erlang/OTP from source.

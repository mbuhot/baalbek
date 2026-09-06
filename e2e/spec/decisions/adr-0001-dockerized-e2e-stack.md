# ADR-0001: The e2e stack is the release image, composed

**Status:** Accepted
**Date:** 2026-09-07
**Stage:** 9

**Context:** PLAN.md's Stage 9 section requires the suite to run against a
containerised stack running the `MIX_ENV=prod` release from Stage 6c, never
`mix phx.server` in dev mode. That settles *what* to run against. It leaves
three things to decide: how the release's schemas get created when Mix — and
therefore every `mix *.bootstrap` task — is absent from a release, how the PWA
is served and how it reaches the API, and how the Moon graph expresses the
edge to an artifact that is not a file.

## Decision

### The stack is four containers in `docker-compose.yml`, owned by the suite

`postgres`, a one-shot `bootstrap`, `server` (`baalbek-server:latest`, from
`moon run server:image`), and `web` (`baalbek-web:latest`, from
`moon run web:image`). Playwright's `globalSetup` brings them up and
`globalTeardown` destroys them, so a run leaves nothing behind and no developer
has to remember a sequence.

**Both tiers run the image that ships.** The first version of this stage got
that right for the server tier and wrong for the web tier: stock nginx plus a
bind-mounted `dist` and a bind-mounted `nginx.conf` that existed nowhere but
`e2e/`. That is the same defect one tier up — testing a configuration nobody
deploys — and it was worse than it looked, because `web/src/api.ts` defaults to
the origin serving the app, so a config file inside the test directory was the
only thing in the repository making that default true. The test harness was
defining the deployment topology. `web/Dockerfile` and `web/nginx.conf.template`
now own it, and the compose file composes that image with no bind mount at all
except the bootstrap script.

`globalSetup` reads the id of each image before the stack starts and asserts
each container runs that exact id. The suite otherwise proves only that
*something* answered on a port; this is what makes "these tests ran against the
release image and the PWA image" a checked fact rather than a claim in a README.
Dropping the bind mounts also makes the stack runnable from inside a container
(a CI job), where a host path in a mount resolves against the wrong filesystem.

Setting `E2E_BASE_URL` runs the same tests against an environment this suite
does not own — a deployed one — and then `globalSetup` starts nothing, checks
no image ids (there are no local containers to check) and tears nothing down.
The first version of this file only *claimed* that: it composed the local stack
regardless and asserted image ids on it while the tests talked to the remote
URL, which is a green run proving something about neither environment.

### Isolation from the dev database is structural, not by convention

A separate Postgres container, in a separate compose project
(`baalbek-e2e`), holding a separate database (`baalbek_e2e`), with its data
directory on `tmpfs` and no published port. The e2e suite writes real rows and
never rolls them back — it drives HTTP, so `Ecto.Adapters.SQL.Sandbox` is not
available to it — and those rows would otherwise land in the same `baalbek`
database `core:test`, `server:test` and every developer share. Nothing here can
reach that database, and nothing there can reach this one.

### Schemas are bootstrapped from inside the release, by `bin/server eval`

`e2e/bootstrap.exs` is mounted into a one-shot container of the release image
and run as `bin/server eval 'Code.require_file("/e2e/bootstrap.exs")'`. It:

1. executes each of `core`'s, `identity`'s and `billing`'s
   `priv/repo/bootstrap.sql` as the Postgres superuser — the same files
   `mix <app>.bootstrap` reads, shipped inside the release under each app's
   `priv/`, split by the same rule (`^;$` on its own line);
2. starts each app and runs `Ecto.Migrator.run(repo, :up, all: true)`, against
   the migrations that likewise travel in the release;
3. calls `:"timeline@bootstrap".main()` — `timeline` is a Gleam application,
   so its bootstrap is a function in the release, not a Mix task.

Everything it runs is therefore an artifact of the release itself. The two
alternatives both fail on that point:

- **Run the bootstrap SQL directly with `psql` from a Postgres container.**
  It covers roles and schemas, and stops there: `core`'s, `identity`'s and
  `billing`'s tables come from Ecto migrations, which are `.exs` files needing
  a BEAM and Ecto to interpret, and `timeline`'s tables come from Gleam code.
  Reimplementing either as static SQL creates a second source of truth that
  drifts silently the first time a migration lands.
- **Add a `Server.Release` module with `migrate/0` to `server`.** The
  canonical Elixir release-task shape, and the right thing to add the day this
  application is deployed for real. Rejected here because Stage 6c decided
  deliberately that "the image runs no migrations and creates no Postgres
  roles or schemas; each app's own bootstrap/migration task owns that", and
  because bootstrapping a *test* database is the e2e suite's concern, not a
  capability the shipped image should grow to satisfy it. A mounted script
  keeps the decision reversible: when a real deployment needs `migrate/0`,
  this file is what it is derived from.

The script is idempotent, like every bootstrap in this repo, so re-creating
the stack costs nothing.

### The PWA image serves the built bundle and proxies `/api` to the release

One origin. The browser loads `index.html` and the hashed bundle that
`web:build` produced and `web/Dockerfile` copied into
`baalbek-web:latest`, and its API calls go to the same host and port, where
nginx forwards them to `SERVER_ORIGIN` (`http://server:4004` in this stack, any
backend elsewhere — it is substituted into the config at container start).

That image has one stage, not the build-then-serve pair `server/Dockerfile`
uses. `server` compiles inside its image because a BEAM release embeds absolute
host paths, host-built NIFs and ERTS; `dist` is portable static output with none
of that. It is also already a shipped artifact in its own right — `mobile`'s
Capacitor bundle embeds the same directory — so building it a second time inside
the image would create a second source of one artifact, free to drift from the
copy `mobile` ships. A build stage would additionally need
`server/priv/static/openapi.json` copied into its context (`core-api-client` is
generated from it, and generating it needs a database), which moves that edge
into the Dockerfile instead of removing it. `web:image`'s `deps` on the
output-declaring `web:build` is what keeps the bundle fresh, which is exactly
the mechanism PLAN.md's task-graph section asks for.

This is the reason the PWA's API base URL now defaults to the origin serving
it (`web/src/api.ts`), instead of the hardcoded `http://localhost:4004`. With
the hardcoded value, a browser on any other port makes a cross-origin request,
and `server` sends no CORS headers, so every request fails — the previous
default only ever worked for a Vite dev server that had the same problem. The
alternatives were to add a CORS plug to `server` (a production-facing change
made solely for a test harness) or to publish the e2e stack on port 4004 so it
matched the compiled-in value (which pins the suite to one port and collides
with a developer's own server). A reverse proxy in front of both is also what
a deployment of this application would look like.

### The origin story, and why no CORS configuration exists anywhere

Three consumers share one `dist`, and none of them needs a CORS grant:

- **Browser**: served by `baalbek-web`, whose nginx proxies `/api` to the
  release. Same origin.
- **This suite**: the same image, on `localhost:4014`. Same proxy, same origin.
- **`mobile`**: a Capacitor WebView, whose origin is the device
  (`capacitor://localhost`, `http://localhost`) and therefore cross-origin to
  any API anywhere — the proxy would not have helped. `CapacitorHttp`
  (`@capacitor/core` 8.5.1, enabled in `mobile/capacitor.config.ts`) patches
  `fetch`/`XMLHttpRequest` to issue **native** requests, which the WebView never
  applies CORS to.

A CORS plug on `server` was implemented and backed out when that third path was
found: it would have been production-facing configuration, on the tier that
needs it least, for a case native HTTP removes entirely. The one deployment that
would genuinely need CORS is a browser PWA served from a different origin than
the API — a CDN in front of the bundle — and `web/nginx.conf.template` is where
it would belong, since that is the tier serving the cross-origin app. Written
down here so a reader does not read the absence as an omission.

Because a packaged app cannot use the same-origin default, `web/public/api-config.js`
holds the base URL as *deploy-time* configuration — a plain script the bundle
loads before its module — and `mobile/scripts/stamp-api-config.sh` rewrites that
one file inside the synced native project. A second, mobile-targeted Vite build
was the alternative; it was rejected because it forks the artifact `mobile`
embeds from the one the web image serves, for a value that is configuration
rather than code, and because baking a URL into a bundle is the compile-time
configuration Stage 6c moved the server tier away from.

Serving the assets from `server` itself was considered and rejected: `server`
is "release assembly; HTTP surface" in PLAN.md's inventory, it has no static
pipeline, and giving it one would mean `web`'s build output has to be inside
the release image — coupling the two artifacts that Stage 6c kept separate.

### The Moon edge: two deps, neither of them hashable

Per PLAN.md's "Task graph: depend on output-declaring tasks" section, `e2e:test`
declares its edges as `deps` on other tasks, and no `project://` inputs. Its two
deps are `server:image` and `web:image`, and neither can declare outputs: an
image in the local docker daemon is not a file, and Moon hashes files.

So the stack is entirely outside `e2e:test`'s hash, and the task sets
`cache: false`. A cache hit would otherwise replay a pass against images that
have since changed, which is the single result this gate must never give — the
same reasoning `timeline:bootstrap` records for the same flag.
Affected-detection is unaffected: `moon ci` propagates it along `deps` whether
or not the upstream declares outputs, and the chain behind `web:image`
(`web:build` → `core-api-client:build` → `server:openapi`) is output-declaring
the whole way, so a source change anywhere under it reaches this task.

Both image tasks — and `root:sandbox-image` behind them — therefore set
`cache: false` too. Moon would otherwise hash their *inputs* and report a cache
hit, replaying a log that claims the image was built, while a `docker image
prune` has since removed it: a build task reporting success and producing
nothing. Docker's own layer cache makes the real rebuild cost seconds.
`globalSetup` still checks both images exist before composing anything, and
names `moon run <project>:image --force` if one does not, because that check
costs nothing and covers whatever else empties a daemon.

## Consequences accepted

- **The suite needs a docker daemon and a free host port** (4014 by default,
  `E2E_HOST_PORT`). It is not runnable in an environment that has neither.
- **Tests share one database and never clean up.** Every row a test creates
  carries a unique suffix (`tests/seed.ts`) and every assertion is scoped to
  the rows that test created, so the suite stays `fullyParallel` and stays
  correct as the database fills up within a run. The database dies with the
  stack, so it never fills up across runs.
- **Playwright browsers are a separate install step** (`playwright install
  chromium`) and their OS-level shared libraries are not in the sandbox/CI
  image yet. See README.md; Stage 12 has to add them for `moon ci`.
- **A PWA change reaches the suite only through `web:image`.** `moon run
  e2e:test` rebuilds it, but a hand-run `playwright test` after an edit to
  `web/src` tests the bundle in the last-built image. The image-id assertion
  cannot catch that: the tag is current, its contents are stale.
- **The service worker is blocked** in the browser context. A precached shell
  can serve markup the stack is no longer serving, which is a false pass. The
  PWA's own installability is `web`'s property to test, not this suite's.

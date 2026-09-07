# timeline

**Language:** Gleam

**Purpose:** Event-sourced technician shift / travel / on-site events;
availability projections.

Owns Postgres schema `timeline`; connects via `pog` as the `timeline` role.
Connection details come from `TIMELINE_PG_HOST`, `TIMELINE_PG_PORT`,
`TIMELINE_PG_DATABASE` and `TIMELINE_PG_PASSWORD`, defaulting to the
`postgres` compose service; `bootstrap` connects as `BOOTSTRAP_PG_USER` /
`BOOTSTRAP_PG_PASSWORD`.

## Local setup

```bash
docker compose -f ../.devcontainer/docker-compose.yml up -d postgres
gleam deps download
gleam run -m timeline/bootstrap   # one-time-per-database: role + schema + tables
gleam test
```

Or via Moon: `moon run timeline:test`.

## Packaging for the BEAM (`moon run timeline:build`)

`scripts/package-otp.sh` writes `build/otp/<app>/ebin/...` — this project and
its runtime dependencies as ordinary OTP application directories, exported
with `gleam export erlang-shipment` so their `.app` files carry real module
lists. `timeline_facade` takes one Mix path dependency per directory, which is
how the Gleam code ends up inside `server`'s release. See
`../server/spec/decisions/adr-0001-release-assembly-and-gleam-packaging.md`.

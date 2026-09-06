# timeline

**Language:** Gleam

**Purpose:** Event-sourced technician shift / travel / on-site events;
availability projections.

Owns Postgres schema `timeline`; connects via `pog` as the `timeline` role.

## Local setup

```bash
docker compose -f ../.devcontainer/docker-compose.yml up -d postgres
gleam deps download
gleam run -m timeline/bootstrap   # one-time-per-database: role + schema + tables
gleam test
```

Or via Moon: `moon run timeline:test`.

`timeline_facade` (Elixir) is this project's sole caller. See
`../timeline_facade/spec/decisions/adr-0001-gleam-elixir-interop.md` for how that
works with no Mix dependency between them.

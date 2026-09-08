# core

**Language:** Elixir / Ash

**Purpose:** Jobs, customers, sites, work orders (field service / job
dispatch domain). `server` publishes its OpenAPI surface.

## What is here

- **Ash resources** (`lib/core/{customer,site,job,work_order}.ex`), grouped
  under the `Core` domain (`lib/core.ex`): `Customer` has many `Site`s, a
  `Site` has many `Job`s, a `Job` has many `WorkOrder`s.
- **`boundary`**: `Core` uses `ash_boundary` — its `exports` derive from the
  domain DSL, since each resource gets a domain-level `define`. `Core.Data`
  (`lib/core/data.ex`) is a nested internal boundary exporting only
  `Core.Data.Repo`; nothing else may talk to Postgres directly.
- **Schema + role**: owns Postgres schema `core`, connects only as the
  dedicated `core` Postgres role (never the superuser). See
  `priv/repo/bootstrap.sql` and `lib/mix/tasks/core.bootstrap.ex`.
- **ExUnit** (`test/core/`): `customer_test.exs` and `job_test.exs` mirror
  their resources, `domain_test.exs` covers the relationships spanning them.
  All run against the real schema/role.

## Acceptance criteria and test selection

- **`spec/features/job_dispatch.feature`** — the acceptance criteria for
  dispatching field work, executed by ExUnit through `cucumber`. Steps and
  the sandbox hook sit beside it in `spec/features/`.
- **`mix test --stale`** runs only the tests whose compile-time
  dependencies changed since the last run.

## Local setup

```bash
# from repo root — brings up the Postgres compose service
docker compose -f .devcontainer/docker-compose.yml up -d postgres

cd core
mix deps.get
mix core.bootstrap        # one-time-per-database: creates role+schema `core`
mix ecto.create && mix ecto.migrate
mix test                   # or: MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate && MIX_ENV=test mix test
```

Or, via Moon (does all of the above): `moon run core:test` from the repo
root.

## Connection defaults

| Env var | Default | Used by |
|---|---|---|
| `CORE_PG_HOST` / `_PORT` / `_DATABASE` | `localhost` / `5432` / `baalbek` | `Core.Data.Repo` (the `core` role) |
| `CORE_PG_USER` / `_PASSWORD` | `core` / `core` | `Core.Data.Repo` |
| `CORE_PG_POOL_SIZE` | `5` (dev), `2` (test) | `Core.Data.Repo` |
| `BOOTSTRAP_PG_HOST` / `_PORT` / `_DATABASE` | `localhost` / `5432` / `baalbek` | `mix core.bootstrap` (superuser) |
| `BOOTSTRAP_PG_USER` / `_PASSWORD` | `postgres` / `postgres` | `mix core.bootstrap` (superuser) |

These match `.devcontainer/docker-compose.yml`'s `postgres` service.

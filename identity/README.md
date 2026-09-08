# identity

**Language:** Elixir / Ash

**Purpose:** Technicians, dispatchers, auth.

Owns Postgres schema `identity`, connecting only as the dedicated `identity`
Postgres role. `Identity.Accounts` (`lib/identity/accounts.ex`) is the domain;
`Identity.Accounts.Account` registers accounts, authenticates them, and
changes passwords, storing only a hash.

## Acceptance criteria and test selection

- **`spec/features/account_access.feature`** — the acceptance criteria for
  technician and dispatcher sign-in, executed by ExUnit through `cucumber`.
  Steps and the sandbox hook sit beside it in `spec/features/`.
- **`mix test --stale`** runs only the tests whose compile-time
  dependencies changed since the last run.

## Local setup

```bash
# from repo root — brings up the Postgres compose service
docker compose -f .devcontainer/docker-compose.yml up -d postgres

cd identity
mix deps.get
mix identity.bootstrap    # one-time-per-database: creates role+schema `identity`
MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
mix test
```

Or, via Moon (does all of the above): `moon run identity:test` from the repo
root.

# billing

**Language:** Elixir / Ash

**Purpose:** Invoices raised from completed jobs.

Owns Postgres schema `billing`, connecting only as the dedicated `billing`
Postgres role. `Billing.Invoicing` (`lib/billing/invoicing.ex`) is the domain;
an invoice references its job by `job_id` alone, with no relationship to
`core`. Its status moves `:draft` -> `:issued` -> `:paid`, with `:void`
reachable from `:draft` or `:issued`.

## Stage 8

- **`spec/features/invoice_lifecycle.feature`** — the acceptance criteria for
  raising, issuing, and paying an invoice, executed by ExUnit through
  `cucumber`. Steps and the sandbox hook sit beside it in `spec/features/`.
- **`mix test --stale`** runs only the tests whose compile-time
  dependencies changed since the last run.

## Local setup

```bash
# from repo root — brings up the Postgres compose service
docker compose -f .devcontainer/docker-compose.yml up -d postgres

cd billing
mix deps.get
mix billing.bootstrap     # one-time-per-database: creates role+schema `billing`
MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
mix test
```

Or, via Moon (does all of the above): `moon run billing:test` from the repo
root.

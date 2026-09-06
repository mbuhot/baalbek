import Config

# Required for AshJsonApi's custom JSON:API mime type — see
# ash_json_api's getting-started guide ("Accept json_api content type").
config :mime,
  extensions: %{"json" => "application/vnd.api+json"},
  types: %{"application/vnd.api+json" => ["json"]}

# `server` has no Ecto Repo or Postgres role/schema of its own: it is a pure
# HTTP/assembly layer (PLAN.md component inventory: "Release assembly; HTTP
# surface") that only ever reaches data through the domain apps' own
# exported functions (`Core.create_customer/1` etc.), never via a direct
# database connection. See server/README.md for the full reasoning.
#
# It DOES, however, take a real Mix path dependency on `core`, `identity`,
# and `billing` (PLAN.md "depends on all domain apps"), and each of those
# apps' `Application` callback starts its own `Ecto.Repo` as part of its
# supervision tree. Mix path dependencies don't load the dependency's own
# `config/config.exs` — only the top-level project's config is evaluated —
# so `server` must replicate the connection settings (and the `:ash`
# global config) those apps' own config files set, or their Repos boot
# with no configuration at all. This is a duplication cost of the poncho
# layout; see the per-app `config/config.exs` files this mirrors.
config :core, Core.Data.Repo,
  username: System.get_env("CORE_PG_USER", "core"),
  password: System.get_env("CORE_PG_PASSWORD", "core"),
  hostname: System.get_env("CORE_PG_HOST", "localhost"),
  port: String.to_integer(System.get_env("CORE_PG_PORT", "5432")),
  database: System.get_env("CORE_PG_DATABASE", "baalbek"),
  pool_size: String.to_integer(System.get_env("CORE_PG_POOL_SIZE", "5"))

config :core, ecto_repos: [Core.Data.Repo]
config :core, ash_domains: [Core]

# `identity` and `billing` are real dependencies (point 1 of this stage) but
# have no wired HTTP surface yet (point 2) — `server` never queries their
# data, so their Repos get plain connection settings only (no per-env
# override), just enough for their `Application.start/2` to boot cleanly.
config :identity, Identity.Repo,
  username: System.get_env("IDENTITY_PG_USER", "identity"),
  password: System.get_env("IDENTITY_PG_PASSWORD", "identity"),
  hostname: System.get_env("IDENTITY_PG_HOST", "localhost"),
  port: String.to_integer(System.get_env("IDENTITY_PG_PORT", "5432")),
  database: System.get_env("IDENTITY_PG_DATABASE", "baalbek"),
  pool_size: String.to_integer(System.get_env("IDENTITY_PG_POOL_SIZE", "2"))

config :identity, ecto_repos: [Identity.Repo]
config :identity, ash_domains: [Identity.Accounts]

config :billing, Billing.Repo,
  username: System.get_env("BILLING_PG_USER", "billing"),
  password: System.get_env("BILLING_PG_PASSWORD", "billing"),
  hostname: System.get_env("BILLING_PG_HOST", "localhost"),
  port: String.to_integer(System.get_env("BILLING_PG_PORT", "5432")),
  database: System.get_env("BILLING_PG_DATABASE", "baalbek"),
  pool_size: String.to_integer(System.get_env("BILLING_PG_POOL_SIZE", "2"))

config :billing, ecto_repos: [Billing.Repo]
config :billing, ash_domains: [Billing.Invoicing]

config :ash, allow_forbidden_field_for_relationships_by_default?: true
config :ash, default_string_length_count: :codepoints

config :server, ash_domains: [Server.Api]

config :server, ServerWeb.Endpoint,
  url: [host: "localhost"],
  # Demo-only placeholder, not a real secret (this repo's Postgres
  # passwords are equally plain — see priv/repo/bootstrap.sql in each
  # domain app). Never reuse this value for a deployed instance.
  secret_key_base:
    "B07epL6m2eS5Y/L+eWUKve+/fVDRZUXYuEhqsqZiHDmMd2Q/T9aT8HYRvKKSI9vZxrUusvuSzCV8pRzz9wrf/w==",
  adapter: Bandit.PhoenixAdapter

import_config "#{config_env()}.exs"

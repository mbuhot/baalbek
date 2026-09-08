import Config

# Required for AshJsonApi's custom JSON:API mime type — see
# ash_json_api's getting-started guide ("Accept json_api content type").
config :mime,
  extensions: %{"json" => "application/vnd.api+json"},
  types: %{"application/vnd.api+json" => ["json"]}

# `server` has no Ecto Repo or Postgres role/schema of its own: it is a pure
# HTTP and assembly layer that only ever reaches data through the domain
# apps' own
# exported functions (`Core.create_customer/1` etc.), never via a direct
# database connection. See server/README.md for the full reasoning.
#
# It DOES, however, take a real Mix path dependency on `core`, `identity`,
# and `billing`, and each of those
# apps' `Application` callback starts its own `Ecto.Repo` as part of its
# supervision tree. Mix path dependencies don't load the dependency's own
# `config/config.exs` — only the top-level project's config is evaluated —
# so `server` must declare what those apps' own config files declare. The
# compile-time half is here; every connection setting is in runtime.exs,
# which a release re-evaluates at boot.
config :core, ecto_repos: [Core.Data.Repo]
config :core, ash_domains: [Core]

config :identity, ecto_repos: [Identity.Repo]
config :identity, ash_domains: [Identity.Accounts]

config :billing, ecto_repos: [Billing.Repo]
config :billing, ash_domains: [Billing.Invoicing]

config :ash, allow_forbidden_field_for_relationships_by_default?: true
config :ash, default_string_length_count: :codepoints

config :server, ash_domains: [Server.Api]

config :server, ServerWeb.Endpoint, adapter: Bandit.PhoenixAdapter

import_config "#{config_env()}.exs"

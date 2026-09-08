import Config

# Required for AshJsonApi's custom JSON:API mime type — see
# ash_json_api's getting-started guide ("Accept json_api content type").
config :mime,
  extensions: %{"json" => "application/vnd.api+json"},
  types: %{"application/vnd.api+json" => ["json"]}

# `server` has no Ecto Repo or Postgres role/schema of its own: it is a pure
# HTTP and assembly layer that only ever reaches data through the domain apps'
# own exported functions (`Core.create_customer/1` etc.), never via a direct
# database connection. See server/README.md for the full reasoning.
#
# It does take a real Mix path dependency on `core`, `identity` and `billing`,
# and `mix compile` here recompiles each of them under *this* config, because a
# Mix path dependency does not load its own config/config.exs. So whatever they
# expect at compile time has to be declared here as well as in their own
# config: `ash_domains`, or Ash warns that the domain is absent from it. Each
# also starts its own `Ecto.Repo` in its supervision tree, hence `ecto_repos`.
# Every connection setting is in runtime.exs, which a release re-evaluates.
config :core, ecto_repos: [Core.Data.Repo]
config :core, ash_domains: [Core]

config :identity, ecto_repos: [Identity.Repo]
config :identity, ash_domains: [Identity.Accounts]

config :billing, ecto_repos: [Billing.Repo]
config :billing, ash_domains: [Billing.Invoicing]

config :ash, allow_forbidden_field_for_relationships_by_default?: true
config :ash, default_string_length_count: :codepoints

config :server, ServerWeb.Endpoint, adapter: Bandit.PhoenixAdapter

import_config "#{config_env()}.exs"

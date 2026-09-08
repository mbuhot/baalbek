import Config

# `identity` owns Postgres schema `identity` and
# connects as the dedicated `identity` Postgres role, never as a superuser —
# see priv/repo/bootstrap.sql for how that role/schema pair is created. The
# role's `search_path` is set to `identity` at the role level by that
# script, so the Ecto Repo below needs no per-query schema prefix: every
# connection made as `identity` already resolves unqualified table names
# inside schema `identity`.
config :identity, Identity.Repo,
  username: System.get_env("IDENTITY_PG_USER", "identity"),
  password: System.get_env("IDENTITY_PG_PASSWORD", "identity"),
  hostname: System.get_env("IDENTITY_PG_HOST", "localhost"),
  port: String.to_integer(System.get_env("IDENTITY_PG_PORT", "5432")),
  database: System.get_env("IDENTITY_PG_DATABASE", "baalbek"),
  # Small pool: identity
  # is an in-process library at this stage, not a service fielding
  # concurrent HTTP requests, so it doesn't need a large pool yet.
  pool_size: String.to_integer(System.get_env("IDENTITY_PG_POOL_SIZE", "5"))

config :identity, ecto_repos: [Identity.Repo]
config :identity, ash_domains: [Identity.Accounts]

config :ash, allow_forbidden_field_for_relationships_by_default?: true

# Recommended per Ash's own guidance: counts unicode codepoints, matching
# how Postgres counts string length, so `min_length`/`max_length`
# constraints are consistent between in-memory validation and the data
# layer. `Identity.Accounts.Account`'s `:password` argument declares a
# min_length constraint, so this matters here.
config :ash, default_string_length_count: :codepoints

import_config "#{config_env()}.exs"

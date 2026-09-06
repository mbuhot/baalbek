import Config

# `core` owns Postgres schema `core` (PLAN.md "Data layer") and connects as
# the dedicated `core` Postgres role, never as a superuser — see
# priv/repo/bootstrap.sql for how that role/schema pair is created. The
# role's `search_path` is set to `core` at the role level by that script, so
# the Ecto Repo below needs no per-query schema prefix: every connection
# made as `core` already resolves unqualified table names inside schema
# `core`.
config :core, Core.Data.Repo,
  username: System.get_env("CORE_PG_USER", "core"),
  password: System.get_env("CORE_PG_PASSWORD", "core"),
  hostname: System.get_env("CORE_PG_HOST", "localhost"),
  port: String.to_integer(System.get_env("CORE_PG_PORT", "5432")),
  database: System.get_env("CORE_PG_DATABASE", "baalbek"),
  # Small pool per PLAN.md "Data layer" ("Size each pool small.") — core is
  # an in-process library at this stage, not a service fielding concurrent
  # HTTP requests, so it doesn't need a large pool yet.
  pool_size: String.to_integer(System.get_env("CORE_PG_POOL_SIZE", "5"))

config :core, ecto_repos: [Core.Data.Repo]
config :core, ash_domains: [Core]

config :ash, allow_forbidden_field_for_relationships_by_default?: true

# Recommended per Ash's own guidance: counts unicode codepoints, matching
# how Postgres counts string length, so `min_length`/`max_length`
# constraints are consistent between in-memory validation and the data
# layer. None of core's resources declare a length constraint yet, but the
# config is mandatory as soon as any :string attribute exists.
config :ash, default_string_length_count: :codepoints

import_config "#{config_env()}.exs"

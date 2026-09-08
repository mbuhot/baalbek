import Config

# `billing` owns Postgres schema `billing` and
# connects as the dedicated `billing` Postgres role, never as a superuser —
# see priv/repo/bootstrap.sql for how that role/schema pair is created. The
# role's `search_path` is set to `billing` at the role level by that
# script, so the Ecto Repo below needs no per-query schema prefix: every
# connection made as `billing` already resolves unqualified table names
# inside schema `billing`.
config :billing, Billing.Repo,
  username: System.get_env("BILLING_PG_USER", "billing"),
  password: System.get_env("BILLING_PG_PASSWORD", "billing"),
  hostname: System.get_env("BILLING_PG_HOST", "localhost"),
  port: String.to_integer(System.get_env("BILLING_PG_PORT", "5432")),
  database: System.get_env("BILLING_PG_DATABASE", "baalbek"),
  # Small pool: billing
  # is an in-process library at this stage, not a service fielding
  # concurrent HTTP requests, so it doesn't need a large pool yet.
  pool_size: String.to_integer(System.get_env("BILLING_PG_POOL_SIZE", "5"))

config :billing, ecto_repos: [Billing.Repo]
config :billing, ash_domains: [Billing.Invoicing]

config :ash, allow_forbidden_field_for_relationships_by_default?: true

# Recommended per Ash's own guidance: counts unicode codepoints, matching
# how Postgres counts string length, so `min_length`/`max_length`
# constraints are consistent between in-memory validation and the data
# layer. None of billing's resources declare a length constraint yet, but
# the config is mandatory as soon as any :string attribute exists (see
# core/config/config.exs, whose comment this mirrors).
config :ash, default_string_length_count: :codepoints

import_config "#{config_env()}.exs"

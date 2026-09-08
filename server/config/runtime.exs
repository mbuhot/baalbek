import Config

# Every setting a deployed release reads from its environment. A release
# has no mix.exs and no config/config.exs — it evaluates this file, and only
# this file, on each boot, so one image runs against any database and port.
# Mix evaluates it too, after config.exs and #{config_env()}.exs, which is
# why the sandbox pool in test.exs and the dev-only flags in dev.exs still
# win: this file never sets those keys.

# `timeline`'s Postgres connection is NOT configured here. It is a Gleam
# application that reads TIMELINE_PG_HOST / TIMELINE_PG_PORT /
# TIMELINE_PG_DATABASE / TIMELINE_PG_PASSWORD from the OS environment
# itself (timeline/src/timeline/db.gleam), not from the application
# environment.

# One connection block per domain app, because Mix path dependencies do not
# load their own config (see server/README.md).
pg = fn prefix, role, pool_size ->
  [
    username: System.get_env("#{prefix}_PG_USER", role),
    password: System.get_env("#{prefix}_PG_PASSWORD", role),
    hostname: System.get_env("#{prefix}_PG_HOST", "localhost"),
    port: String.to_integer(System.get_env("#{prefix}_PG_PORT", "5432")),
    database: System.get_env("#{prefix}_PG_DATABASE", "baalbek"),
    # Small pools: nothing here is throughput-bound.
    pool_size: String.to_integer(System.get_env("#{prefix}_PG_POOL_SIZE", pool_size))
  ]
end

config :core, Core.Data.Repo, pg.("CORE", "core", "5")
config :identity, Identity.Repo, pg.("IDENTITY", "identity", "2")
config :billing, Billing.Repo, pg.("BILLING", "billing", "2")

config :server, ServerWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST", "localhost")],
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4004"))]

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is not set. Generate one with `mix phx.gen.secret`."

  config :server, ServerWeb.Endpoint,
    secret_key_base: secret_key_base,
    # A release boots the endpoint from its own supervision tree; nothing
    # calls `mix phx.server` to turn the listener on.
    server: true

  config :logger, level: :info
else
  # Demo-only placeholder, not a real secret (this repo's Postgres passwords
  # are equally plain). Never reuse this value for a deployed instance.
  config :server, ServerWeb.Endpoint,
    secret_key_base:
      "B07epL6m2eS5Y/L+eWUKve+/fVDRZUXYuEhqsqZiHDmMd2Q/T9aT8HYRvKKSI9vZxrUusvuSzCV8pRzz9wrf/w=="
end

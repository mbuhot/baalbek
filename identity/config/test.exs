import Config

# Ecto's SQL Sandbox wraps each test in a transaction that's rolled back
# afterwards, so tests can run against the real `identity` schema/role
# without leaving data behind or needing serial execution.
config :identity, Identity.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: String.to_integer(System.get_env("IDENTITY_PG_POOL_SIZE", "2"))

config :logger, level: :warning

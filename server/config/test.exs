import Config

# Ecto's SQL Sandbox wraps each test in a transaction that's rolled back
# afterwards — the same pattern `core` itself uses. `server`'s ConnCase
# checks out `Core.Data.Repo` (the only Repo its tests actually exercise).
# The connection settings themselves come from runtime.exs.
config :core, Core.Data.Repo, pool: Ecto.Adapters.SQL.Sandbox

# No HTTP listener needed — Phoenix.ConnTest calls the Endpoint's plug
# pipeline in-process.
config :server, ServerWeb.Endpoint, server: false

config :logger, level: :warning

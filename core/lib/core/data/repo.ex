defmodule Core.Data.Repo do
  @moduledoc """
  `core`'s Ecto Repo (PLAN.md "Data layer": one Ecto Repo per Elixir
  component, connecting as that component's Postgres role, small pool —
  see config/config.exs for the connection details and
  priv/repo/bootstrap.sql for how the `core` role/schema are provisioned).
  """

  use AshPostgres.Repo,
    otp_app: :core,
    # `ash-functions` gives Ash a couple of SQL helper functions (atomics,
    # string_trim, elixir-style `&&`/`||`); we're not using those features
    # at this stage, and installing the extension would require running as
    # a Postgres superuser, which the dedicated `core` role deliberately is
    # not (priv/repo/bootstrap.sql). Revisit if/when a resource needs one
    # of the features the warning lists.
    warn_on_missing_ash_functions?: false

  @impl AshPostgres.Repo
  def installed_extensions do
    # None needed: `uuid_primary_key` generates ids application-side
    # (Ash.UUID.generate/0), not via a Postgres extension function.
    []
  end

  @impl AshPostgres.Repo
  def min_pg_version do
    # .devcontainer/docker-compose.yml pins postgres:17.
    %Version{major: 17, minor: 0, patch: 0}
  end
end

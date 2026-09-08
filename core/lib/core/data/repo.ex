defmodule Core.Data.Repo do
  @moduledoc """
  `core`'s Ecto Repo, connecting as the `core` Postgres role.

  config/config.exs has the connection details, and priv/repo/bootstrap.sql
  provisions the role and schema it connects to.
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

  @doc "No optional Postgres extensions are required."
  @impl AshPostgres.Repo
  def installed_extensions do
    []
  end

  @doc "Requires Postgres 17."
  @impl AshPostgres.Repo
  def min_pg_version do
    %Version{major: 17, minor: 0, patch: 0}
  end
end

defmodule Identity.Repo do
  @moduledoc "Ecto repo for the `identity` schema, connecting to Postgres as the low-privilege `identity` role."

  # top_level?: true lets Identity.Accounts declare `deps [Identity.Repo]` as a sibling boundary.
  use Boundary, top_level?: true, deps: [], exports: []

  use AshPostgres.Repo,
    otp_app: :identity,
    # The `identity` role has no superuser privilege to install the `ash-functions` extension.
    warn_on_missing_ash_functions?: false

  @doc "No optional Postgres extensions are required."
  @impl AshPostgres.Repo
  def installed_extensions do
    []
  end

  @doc "Requires Postgres 17."
  @impl AshPostgres.Repo
  def min_pg_version do
    # .devcontainer/docker-compose.yml pins postgres:17.
    %Version{major: 17, minor: 0, patch: 0}
  end
end

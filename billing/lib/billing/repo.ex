defmodule Billing.Repo do
  @moduledoc "Ecto repo for the `billing` schema, connecting to Postgres as the low-privilege `billing` role."

  # top_level?: true lets Billing.Invoicing declare `deps [Billing.Repo]` as a sibling boundary.
  use Boundary, top_level?: true, deps: [], exports: []

  use AshPostgres.Repo,
    otp_app: :billing,
    # The `billing` role has no superuser privilege to install the `ash-functions` extension.
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

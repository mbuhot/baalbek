defmodule Billing.Repo do
  @moduledoc """
  `billing`'s Ecto Repo (PLAN.md "Data layer": one Ecto Repo per Elixir
  component, connecting as that component's Postgres role, small pool —
  see config/config.exs for the connection details and
  priv/repo/bootstrap.sql for how the `billing` role/schema are
  provisioned).

  Declared `top_level?: true` so `boundary` treats it as its own root
  boundary rather than sweeping it into the `Billing` catch-all boundary
  it's nested under by name — this is what lets `Billing.Invoicing` (a
  sibling boundary, not an ancestor/descendant of this one) declare an
  explicit `deps [Billing.Repo]` to reach it. Exactly the shape
  ash_boundary's own `examples/03_tower/lib/tower/repo.ex` uses.
  """

  use Boundary, top_level?: true, deps: [], exports: []

  use AshPostgres.Repo,
    otp_app: :billing,
    # See core/lib/core/data/repo.ex: the `billing` role deliberately has
    # no superuser privilege to install the `ash-functions` extension, and
    # none of this stage's resources need the features it provides.
    warn_on_missing_ash_functions?: false

  @impl AshPostgres.Repo
  def installed_extensions do
    []
  end

  @impl AshPostgres.Repo
  def min_pg_version do
    # .devcontainer/docker-compose.yml pins postgres:17.
    %Version{major: 17, minor: 0, patch: 0}
  end
end

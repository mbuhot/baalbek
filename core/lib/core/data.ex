defmodule Core.Data do
  @moduledoc """
  Internal data-access boundary exporting only `Core.Data.Repo` (seed.md §3, "Within-app boundaries: boundary").

  Everything that needs to reach Postgres must go through `Core.Data.Repo`;
  nothing outside this boundary may define its own `Ecto.Repo` or otherwise
  talk to the database directly. As a direct child sub-boundary of `Core`,
  its export is automatically visible to `Core` and everything classified
  under it, with no explicit `deps` entry required.
  """

  use Boundary, deps: [], exports: [Repo]
end

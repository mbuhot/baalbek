defmodule Core.Data do
  @moduledoc """
  Internal data-access boundary (seed.md §3, "Within-app boundaries:
  boundary").

  This is `core`'s one real internal boundary at this stage: the only
  module it exports is the Ecto `Repo`. Everything that needs to reach
  Postgres — right now that's only the Ash resources' `AshPostgres.DataLayer`
  configuration — must go through `Core.Data.Repo`; nothing outside this
  boundary may define its own `Ecto.Repo` or otherwise talk to the database
  directly.

  There is exactly one app today (`core` itself), so `boundary` can't yet
  stop a *different* app from reaching in — that only matters once `server`
  (Stage 6) depends on `core`. The point of drawing this boundary now (per
  seed.md §3's rationale) is that the internal split already exists, so nothing
  has to be *retrofitted* later: adding a second data-owning module, or
  splitting `core` itself, starts from a real boundary instead of a fresh
  refactor.
  """

  use Boundary, deps: [], exports: [Repo]
end

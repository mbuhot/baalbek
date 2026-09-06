defmodule Core do
  @moduledoc """
  Public API boundary (seed.md §3, "Within-app boundaries: boundary").

  `core` owns the field-service domain: customers, sites, jobs and work
  orders (PLAN.md's Component inventory: "Jobs, customers, sites, work
  orders."). This boundary's exports are the Ash domain and its resources —
  the only things a caller (in-process today; a future `server` app once
  Stage 6 lands) is meant to touch.

  `Core.Data` (see `lib/core/data.ex`) is a *sub*-boundary nested under this
  one, not a declared `deps` entry: `boundary` forbids a boundary from
  depending on its own descendants, but automatically lets a parent
  boundary's modules (this one, and everything classified under it —
  `Core.Domain`, `Core.Customer`, `Core.Application`, etc.) use whatever a
  direct child sub-boundary exports. `Core.Data` exports only its `Repo`,
  so that's the sole thing reachable — nothing else internal to a future
  sub-boundary would be.
  """

  use Boundary, deps: [], exports: [Domain, Customer, Site, Job, WorkOrder]
end

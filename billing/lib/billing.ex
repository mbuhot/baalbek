defmodule Billing do
  @moduledoc """
  The application's root boundary (PLAN.md's "Boundary enforcement, in-app
  and cross-app" section).

  `Billing.Invoicing` (the Ash domain) and `Billing.Repo` each declare
  their own boundary — `Billing.Invoicing` via `ash_boundary`
  (`use Ash.Domain, extensions: [AshBoundary]`), `Billing.Repo` by hand,
  same as `Tower.Repo` does in ash_boundary's own `examples/03_tower`
  reference. This root boundary covers only what neither of those claims —
  today, just `Billing.Application`, which needs to reach `Billing.Repo`
  to start it in the supervision tree.
  """

  use Boundary, deps: [Billing.Repo]
end

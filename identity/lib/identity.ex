defmodule Identity do
  @moduledoc """
  The application's root boundary (PLAN.md's new "Boundary enforcement,
  in-app and cross-app" section).

  `Identity.Accounts` (the Ash domain) and `Identity.Repo` each declare
  their own boundary — `Identity.Accounts` via `ash_boundary`
  (`use Ash.Domain, extensions: [AshBoundary]`), `Identity.Repo` by hand,
  same as `Tower.Repo` does in ash_boundary's own `examples/03_tower`
  reference. This root boundary covers only what neither of those claims —
  today, just `Identity.Application`, which needs to reach `Identity.Repo`
  to start it in the supervision tree.
  """

  use Boundary, deps: [Identity.Repo]
end

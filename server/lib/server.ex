defmodule Server do
  @moduledoc """
  Root boundary for `server`'s application/domain code.

  Depends on each domain app's own declared public exports (PLAN.md
  "Boundary enforcement, in-app and cross-app") — never their internals,
  e.g. never `Core.Data.Repo` directly. `Server.Api` (this boundary's own
  JSON:API domain, exposed to `ServerWeb`) is listed under `exports`.
  """

  use Boundary,
    deps: [Core, Identity.Accounts, Billing.Invoicing, PricingNative, TimelineFacade],
    exports: [Api, Timeline]
end

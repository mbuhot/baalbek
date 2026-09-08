defmodule Server do
  @moduledoc """
  Root boundary for `server`'s application/domain code.

  Depends on each domain app's own declared public exports, never their
  internals — never `Core.Data.Repo` directly. `Server.Api`, this boundary's
  JSON:API domain, is exposed to `ServerWeb` under `exports`.
  """

  use Boundary,
    deps: [Core, Identity.Accounts, Billing.Invoicing, PricingNative, TimelineFacade],
    exports: [Api, Timeline]
end

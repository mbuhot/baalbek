defmodule Server do
  @moduledoc """
  Root boundary for `server`'s application/domain code.

  Depends on each domain app's own declared public exports, never their
  internals — never `Core.Data.Repo` directly. Each domain declares its own
  JSON:API routes; `ServerWeb` only mounts them.
  """

  use Boundary,
    deps: [Core, Identity.Accounts, Billing.Invoicing, PricingNative, TimelineFacade],
    exports: [Timeline]
end

defmodule Identity.Accounts do
  @moduledoc """
  The identity domain: technicians, dispatchers, and authentication
  (PLAN.md's Component inventory: "Technicians, dispatchers, auth.").

  Uses `ash_boundary` (PLAN.md's "Boundary enforcement, in-app and
  cross-app" section) instead of a hand-rolled `use Boundary` on a plain
  module: `exports` is derived from this domain's DSL — the domain module
  itself, plus every resource with at least one domain-level `define`,
  automatically become the public surface, with everything else in this
  namespace (the password hasher, the change/action implementation
  modules backing `Identity.Accounts.Account`) staying internal.

  `Identity.Accounts.Account` gets three `define`s (`:register`,
  `:authenticate`, `:change_password`), so it is exported — a future
  `server` app (Stage 6) reaches accounts only through these, never by
  building an `Ash.Changeset`/`Ash.Query` against the resource directly.
  """

  use Ash.Domain,
    otp_app: :identity,
    extensions: [AshBoundary]

  boundary do
    deps [Identity.Repo]
  end

  resources do
    resource Identity.Accounts.Account do
      define :register, action: :register
      define :authenticate, action: :authenticate, args: [:email, :password]
      define :change_password, action: :change_password
    end
  end
end

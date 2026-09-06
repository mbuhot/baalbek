defmodule Billing do
  @moduledoc """
  Root Boundary for the `billing` app, giving `Billing.Application` access to `Billing.Repo`.
  """

  use Boundary, deps: [Billing.Repo]
end

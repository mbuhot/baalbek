defmodule Billing do
  @moduledoc """
  Root Boundary for the `billing` app, giving `Billing.Application` access to `Billing.Repo`.
  """

  use Boundary, deps: [Billing.Repo]
end

# Exercise: a first-party Elixir change, to measure what CI rebuilds.

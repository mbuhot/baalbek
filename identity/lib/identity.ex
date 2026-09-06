defmodule Identity do
  @moduledoc """
  Root Boundary for the `identity` app, giving `Identity.Application` access to `Identity.Repo`.
  """

  use Boundary, deps: [Identity.Repo]
end

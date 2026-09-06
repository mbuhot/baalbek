defmodule Identity.Spec.Sandbox do
  @moduledoc "Checks each acceptance scenario out into its own `Identity.Repo` sandbox transaction."

  use Cucumber.Hooks

  before_scenario context do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Identity.Repo)
    {:ok, context}
  end
end

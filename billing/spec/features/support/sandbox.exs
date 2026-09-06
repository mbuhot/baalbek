defmodule Billing.Spec.Sandbox do
  @moduledoc "Checks each acceptance scenario out into its own `Billing.Repo` sandbox transaction."

  use Cucumber.Hooks

  before_scenario context do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Billing.Repo)
    {:ok, context}
  end
end

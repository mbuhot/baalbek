defmodule Server.Spec.Sandbox do
  @moduledoc "Checks each acceptance scenario out into its own `Core.Data.Repo` sandbox transaction."

  use Cucumber.Hooks

  before_scenario context do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Core.Data.Repo)
    {:ok, context}
  end
end

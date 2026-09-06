defmodule Billing.Application do
  @moduledoc "OTP application callback that starts `Billing.Repo` under a one-for-one supervisor."

  use Application

  @doc "Starts the billing supervision tree."
  @impl true
  def start(_type, _args) do
    children = [
      Billing.Repo
    ]

    opts = [strategy: :one_for_one, name: Billing.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

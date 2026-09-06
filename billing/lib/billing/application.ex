defmodule Billing.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Billing.Repo
    ]

    opts = [strategy: :one_for_one, name: Billing.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule Core.Application do
  @moduledoc false

  use Application

  @doc "Starts the core supervision tree."
  @impl true
  def start(_type, _args) do
    children = [
      Core.Data.Repo
    ]

    opts = [strategy: :one_for_one, name: Core.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

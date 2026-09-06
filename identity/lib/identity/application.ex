defmodule Identity.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Identity.Repo
    ]

    opts = [strategy: :one_for_one, name: Identity.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

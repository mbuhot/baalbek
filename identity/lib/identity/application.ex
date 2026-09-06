defmodule Identity.Application do
  @moduledoc "OTP application callback that starts `Identity.Repo` under a one-for-one supervisor."

  use Application

  @doc "Starts the identity supervision tree."
  @impl true
  def start(_type, _args) do
    children = [
      Identity.Repo
    ]

    opts = [strategy: :one_for_one, name: Identity.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

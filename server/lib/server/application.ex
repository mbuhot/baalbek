defmodule Server.Application do
  @moduledoc "OTP application callback that starts the Phoenix endpoint under a one-for-one supervisor."

  use Boundary, top_level?: true, deps: [Server, ServerWeb]
  use Application

  @doc "Starts `server`'s supervision tree (just the Phoenix endpoint — see README for why there's no Repo here)."
  @impl true
  def start(_type, _args) do
    children = [
      ServerWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Server.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc "Required by `Phoenix.Endpoint` for hot code reload; `server` has no live-reloadable config yet."
  @impl true
  def config_change(changed, _new, removed) do
    ServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

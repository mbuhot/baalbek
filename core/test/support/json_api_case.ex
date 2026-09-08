defmodule Core.JsonApiCase do
  @moduledoc """
  Drives `Core`'s JSON:API routes as a bare Plug, with no Phoenix and no HTTP server.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Plug.Test
      import Core.JsonApiCase
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Core.Data.Repo)
    :ok
  end

  @doc "Sends one JSON:API request through the router and decodes the response."
  def request(method, path, body \\ nil) do
    conn =
      Plug.Test.conn(method, path, body && Jason.encode!(body))
      |> Plug.Conn.put_req_header("accept", "application/vnd.api+json")

    conn =
      if body,
        do: Plug.Conn.put_req_header(conn, "content-type", "application/vnd.api+json"),
        else: conn

    conn = Core.JsonApiRouter.call(conn, Core.JsonApiRouter.init([]))

    {conn.status, if(conn.resp_body in [nil, ""], do: nil, else: Jason.decode!(conn.resp_body))}
  end
end

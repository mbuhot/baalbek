defmodule ServerWeb.ConnCase do
  @moduledoc """
  ExUnit case template for tests that make real HTTP requests through `ServerWeb.Endpoint`.

  Builds a fresh `Plug.Conn` with JSON:API headers set. Each test file
  checks out `Core.Data.Repo`'s sandbox itself (the same pattern
  `core/test/core/domain_test.exs` uses) — kept out of this shared,
  normally-compiled support module so it stays boundary-clean: `server`'s
  own code never references `Core.Data.Repo`, only `Core`'s exported
  functions (PLAN.md "Boundary enforcement, in-app and cross-app").
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import ServerWeb.ConnCase

      @endpoint ServerWeb.Endpoint
    end
  end

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn() |> put_json_api_headers()}
  end

  @doc "Sets the JSON:API content type on both the `Accept` and `Content-Type` headers."
  def put_json_api_headers(conn) do
    conn
    |> Plug.Conn.put_req_header("accept", "application/vnd.api+json")
    |> Plug.Conn.put_req_header("content-type", "application/vnd.api+json")
  end
end

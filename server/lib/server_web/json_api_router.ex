defmodule ServerWeb.JsonApiRouter do
  @moduledoc """
  The generated JSON:API router for `Server.Api`.

  Also serves the OpenAPI spec at `/open_api`, and exposes `spec/0` (used by
  `mix openapi.spec.json` — see moon.yml's `openapi` task) since
  `open_api_spex` is a declared dependency.
  """

  use AshJsonApi.Router,
    domains: [Server.Api],
    open_api: "/open_api"
end

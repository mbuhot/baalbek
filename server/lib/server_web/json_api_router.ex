defmodule ServerWeb.JsonApiRouter do
  @moduledoc """
  Serves the JSON:API routes each mounted domain declares, and their OpenAPI
  spec at `/open_api`.
  """

  use AshJsonApi.Router,
    domains: [Core],
    open_api: "/open_api"
end

defmodule ServerWeb.Router do
  @moduledoc "Routes HTTP requests to `core`'s JSON:API surface, mounted under `/api/json/core`."

  use Phoenix.Router

  scope "/api/json" do
    forward "/core", ServerWeb.JsonApiRouter
  end
end

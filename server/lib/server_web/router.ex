defmodule ServerWeb.Router do
  @moduledoc "Routes HTTP requests to `core`'s JSON:API surface and to the technician timeline."

  use Phoenix.Router

  scope "/api/json" do
    forward "/core", ServerWeb.JsonApiRouter
  end

  scope "/api" do
    forward "/timeline", ServerWeb.TimelineRouter
  end
end

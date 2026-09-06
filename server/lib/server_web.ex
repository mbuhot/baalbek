defmodule ServerWeb do
  @moduledoc "Root boundary for `server`'s HTTP layer — the Endpoint, Router, and JSON:API router."

  use Boundary, deps: [Server], exports: [Endpoint, Router, JsonApiRouter]
end

defmodule Core.JsonApiRouter do
  @moduledoc """
  Serves the JSON:API routes `Core`'s resources declare, as a plain Plug.
  """

  use AshJsonApi.Router, domains: [Core]
end

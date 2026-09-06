defmodule ServerWeb.Endpoint do
  @moduledoc "Phoenix endpoint that serves `core`'s JSON:API surface."

  use Phoenix.Endpoint, otp_app: :server

  # Handles file uploads for `:file`-typed action arguments — none exist
  # yet, but there's no cost to including it (ash_json_api's own docs).
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json, AshJsonApi.Plug.Parser],
    pass: ["*/*"],
    json_decoder: Jason

  plug ServerWeb.Router
end

import Config

config :server, ServerWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4004"))],
  check_origin: false,
  debug_errors: true

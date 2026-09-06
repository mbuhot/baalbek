import Config

# Nothing here is compile-time. Everything a production boot needs — the
# database connections, the HTTP port, `secret_key_base` — is read from the
# environment in runtime.exs, so the release image carries no environment of
# its own.

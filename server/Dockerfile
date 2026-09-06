# Runnable `MIX_ENV=prod` release image for `server` — the artifact Stage 9's
# e2e suite runs against (PLAN.md "Stage 9: e2e runs against the dockerized
# release, not a dev server").
#
# Build from the repository root, not from server/: the release assembles all
# five domain apps plus the Gleam `timeline` package, which live in sibling
# directories.
#
#   docker build -f server/Dockerfile -t baalbek-server .
#
# The context is scoped by Dockerfile.dockerignore, which only BuildKit
# reads. Under DOCKER_BUILDKIT=0 the whole workspace is sent as the build
# context instead — correct, but far slower.
#
# Two stages. The build stage is the repository's own sandbox/CI image (root
# Dockerfile), so the release is compiled by the exact proto-pinned toolchain
# every other task uses — no second, drifting toolchain definition. The
# runtime stage carries only the assembled release, which embeds ERTS, and the
# shared libraries ERTS and the Rustler NIF link against.
#
# Configuration is entirely by environment variable at boot, read by
# server/config/runtime.exs and timeline/src/timeline/db.gleam:
#
#   SECRET_KEY_BASE   required, no default
#   PORT              default 4004
#   PHX_HOST          default localhost
#   CORE_PG_*, IDENTITY_PG_*, BILLING_PG_*   USER/PASSWORD/HOST/PORT/DATABASE/POOL_SIZE
#   TIMELINE_PG_HOST, TIMELINE_PG_PORT, TIMELINE_PG_DATABASE, TIMELINE_PG_PASSWORD
#
# The image runs no migrations and creates no Postgres roles or schemas; each
# app's own bootstrap/migration task owns that.

ARG BUILDER_IMAGE=baalbek-sandbox:latest
ARG RUNTIME_IMAGE=debian:bookworm-slim

FROM ${BUILDER_IMAGE} AS build

USER vscode
WORKDIR /workspace
ENV MIX_ENV=prod
# proto's rust plugin installs through rustup, which puts cargo here rather
# than under PROTO_HOME. Rustler shells out to `cargo` to build the NIF.
ENV PATH="/home/vscode/.cargo/bin:${PATH}"

COPY --chown=vscode:vscode .prototools .prototools
RUN proto install

# timeline first, and on its own layer: its packaged OTP applications are an
# input to timeline_facade's mix.exs, and its sources change independently of
# the Elixir apps'.
COPY --chown=vscode:vscode timeline timeline
RUN bash timeline/scripts/package-otp.sh

COPY --chown=vscode:vscode core core
COPY --chown=vscode:vscode identity identity
COPY --chown=vscode:vscode billing billing
COPY --chown=vscode:vscode pricing pricing
COPY --chown=vscode:vscode pricing_native pricing_native
COPY --chown=vscode:vscode timeline_facade timeline_facade
COPY --chown=vscode:vscode server server

WORKDIR /workspace/server
RUN mix local.hex --force --if-missing \
    && mix local.rebar --force --if-missing \
    && mix deps.get --only prod \
    && mix release --overwrite

FROM ${RUNTIME_IMAGE} AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# libssl3/libncurses6/libstdc++6 are what the release's embedded ERTS and the
# Rustler NIF link against; curl backs the HEALTHCHECK below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libncurses6 \
        libssl3 \
        libstdc++6 \
        locales \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash app
USER app
WORKDIR /app

COPY --from=build --chown=app:app /workspace/server/_build/prod/rel/server /app

EXPOSE 4004

# The OpenAPI document is generated from the compiled Ash resources and needs
# no database, so this reports "the HTTP surface is up" without also asserting
# Postgres is reachable.
HEALTHCHECK --interval=5s --timeout=3s --start-period=20s --retries=12 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-4004}/api/json/core/open_api" > /dev/null

ENTRYPOINT ["/app/bin/server"]
CMD ["start"]

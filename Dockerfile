# Sandbox / CI image for the baalbek modular monolith.
#
# Language toolchains (Erlang, Elixir, Gleam, Rust, Node, pnpm, moon) are NOT
# installed via apt or any other ad hoc mechanism. proto (https://moonrepo.dev/proto)
# owns every language toolchain version end-to-end, pinned in the repo's root
# .prototools and resolved by `proto install` below. This image only provides:
#
#   1. proto itself,
#   2. the OS-level build dependencies proto's asdf backend needs to compile
#      Erlang/OTP from source, and that `cargo`/rustler need to build native
#      extensions,
#   3. the Postgres 17 *client* libraries/CLI (the Postgres *server* is a
#      docker-compose service, per PLAN.md's "Sandbox" section — it is
#      deliberately not baked into this image).
#
# Same image is used for the sandbox/devcontainer and for CI, so an
# under-declared task input surfaces as an immediate failure rather than a
# stale-cache pass.

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# --- OS build dependencies -------------------------------------------------
#
# Split into groups so the reason for each package is traceable:
#
#  * generic toolchain / fetch:
#      build-essential (gcc/g++/make), git, curl, ca-certificates, gnupg,
#      pkg-config, unzip, xz-utils (proto's own release archives are .tar.xz),
#      file, locales
#
#  * Erlang/OTP build-from-source (asdf:erlang), per the official OTP
#    "Required" + commonly-needed optional list:
#      autoconf, m4, libncurses-dev, libssl-dev (crypto/ssl/otp ssl app),
#      unixodbc-dev (odbc app), libsctp-dev (sctp), zlib1g-dev
#    wxWidgets (for wx/debugger/observer/et's GUIs) and doc-build toolchains
#    (fop/xsltproc/openjdk) are intentionally NOT installed: this is a
#    headless server build. Verified in this sandbox: unlike most optional
#    OTP apps, wx-*based* apps' builds (not just their runtime GUIs) hard-
#    fail when wxWidgets dev headers are absent — configure only warns, but
#    `make` still tries to compile their wx-dependent modules (lib/wx itself,
#    plus lib/debugger/src/dbg_wx_*.erl, lib/observer's and lib/et's wx
#    frontends) and errors out, which stops the whole build. So each must be
#    explicitly disabled via KERL_CONFIGURE_OPTIONS (set below) rather than
#    relying on graceful degradation.
#
#  * Rustler NIF builds (pricing_native, moon-elixir-plugin's own tooling):
#      build-essential + pkg-config + libssl-dev (already listed above) cover
#      the usual crate needs; cargo/rustc themselves come from proto's rust
#      plugin, not apt.
#
#  * Postgres 17 client libraries, for later Ecto/Postgrex and Gleam `pog`
#    work (wire-protocol drivers that don't strictly need libpq, but psql
#    and libpq headers are kept on hand for migrations/debugging tooling):
#      postgresql-client-17, libpq-dev
#    Debian bookworm's own repos only ship the Postgres 15 client, so the
#    PGDG apt repo is added first to get 17.

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        curl \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        pkg-config \
        unzip \
        xz-utils \
        file \
        locales \
        autoconf \
        m4 \
        libncurses-dev \
        libssl-dev \
        unixodbc-dev \
        libsctp-dev \
        zlib1g-dev \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client-17 \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# --- Non-root user ----------------------------------------------------------
# Matches the devcontainer's default `vscode` remote user convention.
RUN useradd --create-home --shell /bin/bash vscode \
    && mkdir -p /workspace \
    && chown vscode:vscode /workspace

# Debian bookworm-slim's /etc/profile unconditionally does
# PATH="/usr/local/sbin:...:/bin"; export PATH, which discards the ENV PATH
# set below for any *login* shell (bash -l / bash --login) — non-login
# shells (VS Code's integrated terminal, `docker exec`, RUN/postCreateCommand
# steps) are unaffected since they don't source /etc/profile. Drop a
# profile.d script so login shells keep proto (and everything it manages) on
# PATH too.
RUN printf '%s\n' \
        'export PROTO_HOME="/home/vscode/.proto"' \
        'export PATH="$PROTO_HOME/bin:$PATH"' \
        > /etc/profile.d/proto.sh \
    && chmod +r /etc/profile.d/proto.sh

USER vscode
WORKDIR /home/vscode

# --- proto -------------------------------------------------------------
# Nothing language-related beyond this point: every version below comes from
# the repo's own /workspace/.prototools at `proto install` time.
ENV PROTO_HOME="/home/vscode/.proto"
ENV PATH="${PROTO_HOME}/bin:${PATH}"

# See the wx note above: proto's asdf:erlang backend shells out to kerl,
# which honours this env var when building OTP from source.
ENV KERL_CONFIGURE_OPTIONS="--without-wx --without-debugger --without-observer --without-et"

RUN curl -fsSL https://moonrepo.dev/install/proto.sh -o /tmp/proto-install.sh \
    && bash /tmp/proto-install.sh --yes --no-modify-profile --no-modify-path \
    && rm -f /tmp/proto-install.sh

# Warm the toolchain layer: build/download every version pinned in
# .prototools (moon, node, pnpm, rust, and Erlang/Elixir/Gleam via proto's
# asdf backend) at image-build time, so a fresh container never pays that
# cost on first `moon run`.
WORKDIR /workspace
COPY --chown=vscode:vscode .prototools .prototools
RUN proto install

# === Everything below is appended after the toolchain layer ================
#
# New packages and settings go here, never into the apt list or the ENV/RUN
# steps above. Those are inputs to `proto install`'s from-source Erlang/OTP
# build, so touching one forces a full OTP recompile, and the task chain
# `e2e:test` -> `server:image` -> `root:sandbox-image` would drag that
# recompile into the e2e gate. PLAN.md's "Adding OS packages after the fact"
# states the rule and says when to consolidate.

# --- OS packages for tasks that run in this image ---------------------------
#
#  * Python 3. `root:test` runs test-paths.py, every Elixir app's
#    `mix test.changed` calls it to select tests, and two shell scripts parse
#    `moon query` output with it. Debian's slim base carries no interpreter.
#
#  * Chromium's shared libraries, for `e2e:test`, which drives a real browser
#    from this image against the composed release stack. The list is
#    playwright-core 1.63.0's own `debian12` chromium set, read out of its
#    nativeDeps table rather than guessed, plus fontconfig and one font family
#    so text renders at all. Playwright downloads the browser binary itself
#    into ~/.cache/ms-playwright; only these OS libraries have to be baked in.
#
#  * Docker CLI, the Buildx plugin and the Compose v2 plugin.
#    `root:sandbox-image`, `server:image`, `web:image` and `e2e:test` all shell
#    out to `docker`, and CI runs those tasks from inside this image against the
#    host daemon's mounted socket
#    (spec/decisions/adr-0007-ci-runs-moon-ci-inside-the-sandbox-image.md).
#    Buildx is not optional: without it `docker build` falls back to the legacy
#    builder, which shares no cache with the daemon's BuildKit, so
#    `root:sandbox-image` rebuilds Erlang/OTP from source. The three image
#    tasks name `docker buildx build` so a missing plugin errors instead.
#    No daemon is installed here; the devcontainer gets one from its
#    docker-in-docker feature.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        libasound2 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libatspi2.0-0 \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libdrm2 \
        libgbm1 \
        libglib2.0-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libx11-6 \
        libxcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        fontconfig \
        fonts-liberation \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# proto puts `pnpm` in $PROTO_HOME/shims only — $PROTO_HOME/bin has no entry
# for it — so every `toolchain: "node"` task needs the shims directory too.
# Appended to the existing script rather than folded into it, for the layer
# reason above; $PROTO_HOME is already exported by its first line.
RUN printf '%s\n' 'export PATH="$PATH:$PROTO_HOME/shims"' >> /etc/profile.d/proto.sh

USER vscode
ENV PATH="${PATH}:${PROTO_HOME}/shims"

# Hex and rebar3 come from Mix, not apt or proto. Without them the first
# `mix deps.get` in a fresh container prompts to install Hex, reads EOF from a
# non-interactive stdin, and fails. MIX_HOME/HEX_HOME are pinned so they stay
# found when a caller overrides HOME.
ENV MIX_HOME="/home/vscode/.mix" \
    HEX_HOME="/home/vscode/.hex"
RUN mix local.hex --force && mix local.rebar --force

CMD ["bash"]

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
# Same image serves the devcontainer, `server:image`, and the cold full-graph
# gate in .github/workflows/image-gate.yml.

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# --- OS build dependencies -------------------------------------------------
# One list, shared with the CI runner. wxWidgets is absent, so
# KERL_CONFIGURE_OPTIONS below must disable the wx-based OTP applications.

COPY scripts/install-os-deps.sh /tmp/install-os-deps.sh
RUN bash /tmp/install-os-deps.sh toolchain

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
# Settings go here, never into the ENV/RUN steps above, which are inputs to
# `proto install`'s from-source Erlang/OTP build. An OS package added to either
# group of the script COPYed above invalidates that build; adr-0009 records why
# PLAN.md's "Adding OS packages after the fact" rule for it.

# --- OS packages for tasks that run in this image ---------------------------
# No Docker daemon; the devcontainer gets one from its docker-in-docker feature.
USER root
RUN bash /tmp/install-os-deps.sh tasks

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

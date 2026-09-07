#!/usr/bin/env bash
# `moon-elixir-plugin:build`: compiles the WASM artifact ../.moon/toolchains.yml
# loads, and refuses to replace the committed one with different bytes.
#
# In a script rather than inline moon.yml `args` because moon pre-substitutes
# `$IDENTIFIER` from its own environment, which mangles the `${VAR:-default}`
# the remap prefix needs.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ARTIFACT="plugin/moon_elixir_plugin.wasm"

# Redirected under $HOME for the virtiofs reason ../pricing/moon.yml documents.
export CARGO_TARGET_DIR="$HOME/.cache/baalbek-cargo-target/moon-elixir-plugin"

# A release build bakes every `panic!` location into the artifact as data, and
# for a registry dependency that location is an absolute path under
# $CARGO_HOME — which follows $HOME, so it differs for every user and on every
# CI runner. `strip` does not remove them. Without this remap the same source
# and the same rustc produce different bytes on each machine, and the
# comparison below fails everywhere except where the artifact was last built.
# rustc's own standard-library paths are already virtualised as /rustc/<hash>,
# so the registry is the only prefix that needs remapping.
export CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo"

# The wasm32-wasip1 target comes from the rustup that proto's rust plugin
# installs, added on demand rather than baked into the sandbox image so the OTP
# layer stays cached (PLAN.md "Adding OS packages after the fact").
if ! rustup target list --installed | grep -qx wasm32-wasip1; then
  rustup target add wasm32-wasip1
fi

cargo build --target wasm32-wasip1 --release

# `cat` rather than `cp` for the reflink reason ../pricing/moon.yml documents.
mkdir -p plugin
cat "${CARGO_TARGET_DIR}/wasm32-wasip1/release/moon_elixir_plugin.wasm" > "${ARTIFACT}.new"

# Compared against the *committed* bytes, and compared before the rename. The
# comparison is what makes a stale commit impossible; doing it first is what
# keeps a failing task from leaving a tracked artifact modified.
if ! git show ":./${ARTIFACT}" | cmp - "${ARTIFACT}.new"; then
  echo "moon-elixir-plugin: the committed ${ARTIFACT} is not what this source builds." >&2
  echo "The fresh bytes are in ${ARTIFACT}.new; commit them if the change is intended." >&2
  exit 1
fi

mv "${ARTIFACT}.new" "${ARTIFACT}"

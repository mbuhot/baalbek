#!/usr/bin/env bash
# `moon-elixir-plugin:build`: compiles the WASM artifact ../.moon/toolchains.yml
# loads, and checks the committed one was built from this source.
#
# `--accept` records a rebuilt artifact as the committed one. Nothing else
# writes the tracked files, so a failing check never leaves them modified.
#
# In a script rather than inline moon.yml `args` because moon pre-substitutes
# `$IDENTIFIER` from its own environment, which mangles the `${VAR:-default}`
# the remap prefix needs.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ARTIFACT="plugin/moon_elixir_plugin.wasm"

case "${1:-}" in
  "") MODE="check" ;;
  --accept) MODE="accept" ;;
  *) echo "usage: build.sh [--accept]" >&2; exit 2 ;;
esac

# Redirected under $HOME for the input-glob reason ../pricing/moon.yml documents.
export CARGO_TARGET_DIR="$HOME/.cache/baalbek-cargo-target/moon-elixir-plugin"

# A release build bakes every `panic!` location into the artifact as data, and
# for a registry dependency that location is an absolute path under
# $CARGO_HOME — which follows $HOME, so it differs for every user and on every
# CI runner. `strip` does not remove them. rustc's own standard-library paths
# are already virtualised as /rustc/<hash>, so the registry is the only prefix
# that needs remapping.
export CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=${CARGO_HOME:-$HOME/.cargo}=/cargo"

# The wasm32-wasip1 target comes from the rustup that proto's rust plugin
# installs, added on demand rather than baked into the sandbox image so the
# OTP layer stays cached.
if ! rustup target list --installed | grep -qx wasm32-wasip1; then
  rustup target add wasm32-wasip1
fi

# `--locked` because the provenance record names the committed dependency
# versions. Without it a Cargo.lock that no longer satisfies Cargo.toml is
# re-resolved silently, and a machine with a fresher crates.io index then
# builds different code from the same commit.
cargo build --locked --target wasm32-wasip1 --release

mkdir -p plugin
cp "${CARGO_TARGET_DIR}/wasm32-wasip1/release/moon_elixir_plugin.wasm" "${ARTIFACT}.new"

# The gate asserts provenance, not byte-equality: the same source does not
# produce the same bytes on a different host architecture, which
# spec/decisions/adr-0002 records along with the rest of this rule.
bash scripts/provenance.sh "${MODE}"

rm -f "${ARTIFACT}.new"

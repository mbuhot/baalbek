#!/usr/bin/env bash
# Moon task body for timeline:test.
set -euo pipefail

# Prefer proto's direct activated binaries over its shims. Moon's PATH
# puts shims first, and the shim for asdf:erlang cannot locate a primary
# executable (its plugin marks none as primary), so any mix/gleam call
# that shells out to erl fails. Prepending here fixes that.
export PATH="${PROTO_HOME:-$HOME/.proto}/bin:$PATH"

# rebar3 builds pog's transitive Erlang-native deps. proto doesn't manage
# it; mix local.rebar fetches it (idempotent).
mix local.rebar --if-missing --force

mix_home="${MIX_HOME:-$HOME/.mix}"
rebar3_path="$(find "$mix_home" -type f -name rebar3 | head -1)"
if [ -z "$rebar3_path" ]; then
  echo "moon-test.sh: no rebar3 found under $mix_home after mix local.rebar" >&2
  exit 1
fi
export PATH="$(dirname "$rebar3_path"):$PATH"

# Bootstrap the timeline role/schema/tables (idempotent).
gleam run -m timeline/bootstrap

gleam test

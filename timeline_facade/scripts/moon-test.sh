#!/usr/bin/env bash
# Moon task body for timeline_facade:test.
set -euo pipefail

# Prefer proto's direct activated binaries over its shims (see
# ../../timeline/scripts/moon-test.sh for why).
export PATH="${PROTO_HOME:-$HOME/.proto}/bin:$PATH"

mix deps.get

# Compensating check: boundary cannot classify Gleam's bare-atom modules,
# so it cannot enforce "sole caller of :timeline" here. See
# spec/decisions/adr-0001-gleam-elixir-interop.md.
matches="$(grep -rn ':timeline\.' lib --include='*.ex' 2>/dev/null | grep -v '^lib/timeline_facade/gleam.ex:' || true)"
if [ -n "$matches" ]; then
  echo "$matches"
  echo 'boundary-compensating check failed: direct :timeline reference outside TimelineFacade.Gleam'
  exit 1
fi

mix test

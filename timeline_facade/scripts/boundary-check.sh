#!/usr/bin/env bash
# Moon task body for timeline_facade:boundary-check.
#
# Compensating check: boundary cannot classify Gleam's bare-atom modules, so
# it cannot enforce "sole caller of :timeline" here. See
# spec/decisions/adr-0001-gleam-elixir-interop.md.
set -euo pipefail

cd "$(dirname "$0")/.."

matches="$(grep -rn ':timeline\.' lib --include='*.ex' 2>/dev/null | grep -v '^lib/timeline_facade/gleam.ex:' || true)"
if [ -n "$matches" ]; then
  echo "$matches"
  echo 'boundary-compensating check failed: direct :timeline reference outside TimelineFacade.Gleam'
  exit 1
fi

#!/usr/bin/env bash
# Answers whether this run's affected tasks include the one that builds the
# sandbox image. Exit 0 means yes, 1 means no.
#
# `root:sandbox-image` is the only task that produces the image, so everything
# needing it reaches it through that one target.
#
# A wrong answer costs a slow build, never a wrong one: without the warm
# BuildKit cache `root:sandbox-image` still builds, from source.
set -euo pipefail

TARGET="root:sandbox-image"

# No base means moon treats the whole graph as affected.
if [ -z "${MOON_BASE:-}" ]; then
  echo "affected: no base ref, so the whole graph is affected and ${TARGET} is in it"
  exit 0
fi

# Take the document that has `tasks`, not the first one: moon prefixes its
# stdout with an NDJSON notice when it activates a toolchain.
targets="$(moon query tasks --affected --upstream deep |
  sed -n '/{/,$p' | sed '1s/^[^{]*//' |
  jq -r -n '[ inputs | select(has("tasks")) ] | first.tasks // {} | .[] | .[] | .target')"

count="$(printf '%s' "$targets" | grep -c . || true)"

if printf '%s\n' "$targets" | grep -qxF "$TARGET"; then
  echo "affected: ${TARGET} is in the affected set (${count} tasks)"
  exit 0
fi

echo "affected: ${TARGET} is not in the affected set (${count} tasks)"
exit 1

#!/usr/bin/env bash
# `mobile:build`'s own command (PLAN.md Stage 7 gate). `build-android` is
# a real `deps` edge in moon.yml, so moon runs it; this script's only job
# is every OTHER mobile task tagged `requires-macos` — run on macOS,
# explicitly logged as skipped elsewhere.
#
# Queries the positive tag case: moon 2.5.4's negated `taskTag!=` and
# `taskTag!~` both return an empty set, so they cannot express "every task
# without this tag".
set -euo pipefail

# Parsed defensively: under concurrent load (a workspace-wide sweep) moon has
# been seen writing more than the one JSON document to stdout, which a plain
# json.load reports as an unreadable traceback.
query_stderr="$(mktemp)"
if ! query_output="$(moon query tasks --project mobile 'taskTag=requires-macos' 2> "$query_stderr")"; then
  echo "mobile:build: \`moon query tasks\` failed:" >&2
  cat "$query_stderr" >&2
  exit 1
fi
rm -f "$query_stderr"

# Read from the first `{` and take one document: under load, moon's stdout has
# been seen carrying log noise ahead of its JSON and more than one document.
macos_tasks="$(printf '%s' "$query_output" |
  sed -n '/{/,$p' | sed '1s/^[^{]*//' |
  jq -r -n 'input.tasks.mobile // {} | keys[]')"

for t in $macos_tasks; do
  if [ "$(uname -s)" = "Darwin" ]; then
    moon run "mobile:$t"
  else
    echo "skipped: requires-macos, not available in this environment (mobile:$t)"
  fi
done

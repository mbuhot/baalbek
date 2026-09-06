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

macos_tasks="$(moon query tasks --project mobile 'taskTag=requires-macos' 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('\n'.join(d['tasks'].get('mobile', {}).keys()))")"

for t in $macos_tasks; do
  if [ "$(uname -s)" = "Darwin" ]; then
    moon run "mobile:$t"
  else
    echo "skipped: requires-macos, not available in this environment (mobile:$t)"
  fi
done

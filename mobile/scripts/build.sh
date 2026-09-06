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
query_output="$(moon query tasks --project mobile 'taskTag=requires-macos' 2>/dev/null)"

macos_tasks="$(python3 - "$query_output" <<'PY'
import json
import sys

raw = sys.argv[1]
start = raw.find("{")
if start == -1:
    sys.exit(f"mobile:build: `moon query tasks` printed no JSON object:\n{raw[:500]}")

try:
    # raw_decode reads the first JSON value and ignores whatever follows it.
    document, _ = json.JSONDecoder().raw_decode(raw[start:])
except json.JSONDecodeError as error:
    sys.exit(f"mobile:build: could not parse `moon query tasks` output ({error}):\n{raw[:500]}")

print("\n".join(document.get("tasks", {}).get("mobile", {}).keys()))
PY
)"

for t in $macos_tasks; do
  if [ "$(uname -s)" = "Darwin" ]; then
    moon run "mobile:$t"
  else
    echo "skipped: requires-macos, not available in this environment (mobile:$t)"
  fi
done

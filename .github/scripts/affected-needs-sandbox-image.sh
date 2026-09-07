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

query_output="$(moon query tasks --affected --upstream deep)"

python3 - "$query_output" "$TARGET" <<'PY'
import json
import sys

raw, target = sys.argv[1], sys.argv[2]
start = raw.find("{")
if start == -1:
    sys.exit(f"affected-needs-sandbox-image: `moon query tasks` printed no JSON object:\n{raw[:500]}")

# raw_decode ignores whatever follows, per report-excluded-tasks.sh.
document, _ = json.JSONDecoder().raw_decode(raw[start:])

targets = {
    task["target"] for tasks in document.get("tasks", {}).values() for task in tasks.values()
}

if target in targets:
    print(f"affected: {target} is in the affected set ({len(targets)} tasks)")
    sys.exit(0)

print(f"affected: {target} is not in the affected set ({len(targets)} tasks)")
sys.exit(1)
PY

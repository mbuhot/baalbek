#!/usr/bin/env bash
# Names every task `moon ci` will not run, before it runs.
#
# `runInCI: false` is the only setting that drops a task from `moon ci`, so that
# is what this reads; the task's tags carry the reason and are printed with it.
# A task excluded with no tag fails this check, because an exclusion nobody can
# read is how a suite quietly stops being run.
set -euo pipefail

# stderr is deliberately not swallowed: a workspace moon cannot load should say
# so here, not exit 1 with nothing.
query_file="$(mktemp)"
trap 'rm -f "$query_file"' EXIT
moon query tasks > "$query_file"
echo "moon query tasks: $(wc -c < "$query_file") bytes"

# Read from a file, not argv: this JSON exceeds the 128 KiB one-argument limit
# on a 4 KiB-page runner.
# Parsed defensively for the reason mobile/scripts/build.sh documents: under
# load, moon's stdout has been seen carrying more than the one JSON document.
python3 - "$query_file" <<'PY'
import json
import sys

raw = open(sys.argv[1], encoding="utf-8").read()
start = raw.find("{")
if start == -1:
    sys.exit(f"report-excluded-tasks: `moon query tasks` printed no JSON object:\n{raw[:500]}")

try:
    # raw_decode reads the first JSON value and ignores whatever follows it.
    document, _ = json.JSONDecoder().raw_decode(raw[start:])
except json.JSONDecodeError as error:
    sys.exit(f"report-excluded-tasks: could not parse `moon query tasks` output ({error}):\n{raw[:500]}")

excluded = []
for tasks in document.get("tasks", {}).values():
    for task in tasks.values():
        if not task.get("options", {}).get("runInCI", True):
            excluded.append((task["target"], task.get("tags") or []))
excluded.sort()

if not excluded:
    print("moon ci excludes no tasks in this workspace.")
    sys.exit(0)

print("moon ci will NOT run these tasks (runInCI: false):")
untagged = []
for target, tags in excluded:
    print(f"  {target} — {', '.join(tags) if tags else 'NO TAG'}")
    if not tags:
        untagged.append(target)

if untagged:
    sys.exit("report-excluded-tasks: excluded with no tag saying why: " + ", ".join(untagged))
PY

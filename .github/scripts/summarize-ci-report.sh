#!/usr/bin/env bash
# Says how much work a `moon ci` run actually did, from the run's own report.
#
#   .github/scripts/summarize-ci-report.sh [path-to-ciReport.json]
#
# Reads moon's report rather than re-deriving anything, and never fails: a
# missing report is announced, not turned into a second failure.
set -uo pipefail

REPORT="${1:-.moon/cache/ciReport.json}"

if [ ! -f "${REPORT}" ]; then
  echo "=================================================================="
  echo "moon ci report: NOT WRITTEN at ${REPORT}"
  echo "moon ci report: a run with no affected tasks writes none; any other"
  echo "moon ci report: case means the pipeline died before reporting."
  echo "=================================================================="
  exit 0
fi

python3 - "${REPORT}" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    report = json.load(handle)


def seconds(value):
    if not value:
        return 0.0
    return value.get("secs", 0) + value.get("nanos", 0) / 1_000_000_000


def op_types(action):
    return {op.get("meta", {}).get("type") for op in (action.get("operations") or [])}


tasks = [a for a in report.get("actions", []) if a["label"].startswith("RunTask(")]
executed = [a for a in tasks if "task-execution" in op_types(a)]
executed_labels = {a["label"] for a in executed}
replayed = [
    a for a in tasks if "output-hydration" in op_types(a) and a["label"] not in executed_labels
]
skipped = [a for a in tasks if a["status"] == "skipped"]
failed = [a for a in tasks if a["status"] in ("failed", "aborted", "timed-out")]

lines = []
lines.append(f"**moon ci:** {report.get('status', 'unknown')} in {seconds(report.get('duration')):.1f}s")
lines.append("")
lines.append(f"- **{len(executed)}** tasks executed")
lines.append(f"- **{len(replayed)}** replayed from cache")
lines.append(f"- **{len(skipped)}** skipped")
if failed:
    lines.append(f"- **{len(failed)}** failed: " + ", ".join(a["label"] for a in failed))

affected = (report.get("context") or {}).get("affected") or {}
projects = affected.get("projects") or {}
if projects:
    lines.append("")
    lines.append("Affected by the changed files:")
    lines.append("")
    for name in sorted(projects):
        entry = projects[name] or {}
        selected = ", ".join(entry.get("tasks") or []) or "(no tasks)"
        lines.append(f"- `{name}` — {selected}")
        for path in (entry.get("files") or [])[:5]:
            lines.append(f"  - `{path}`")
else:
    lines.append("")
    lines.append("No project was reported affected by the changed files.")

if executed:
    lines.append("")
    lines.append("Slowest executed tasks:")
    lines.append("")
    for action in sorted(executed, key=lambda a: seconds(a.get("duration")), reverse=True)[:8]:
        label = action["label"][len("RunTask(") : -1]
        lines.append(f"- `{label}` {seconds(action.get('duration')):.1f}s")

text = "\n".join(lines)
print(text)

summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a", encoding="utf-8") as handle:
        handle.write(text + "\n\n")
PY

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

# Read from the first `{` and take one document: under load, moon's stdout has
# been seen carrying log noise ahead of its JSON and more than one document.
excluded="$(sed -n '/{/,$p' "$query_file" | sed '1s/^[^{]*//' | jq -r -n '
  [ input.tasks // {} | .[] | .[]
    # `== false`, not `// true`: the `//` operator in jq treats a `false`
    # value as absent, so it would read this very setting as its default.
    | select(.options.runInCI == false)
    | { target, tags: (.tags // []) } ]
  | sort_by(.target)[]
  | "  \(.target) — \(if (.tags | length) > 0 then (.tags | join(", ")) else "NO TAG" end)"
')"

if [ -z "$excluded" ]; then
  echo "moon ci excludes no tasks in this workspace."
  exit 0
fi

echo "moon ci will NOT run these tasks (runInCI: false):"
printf '%s\n' "$excluded"

untagged="$(printf '%s\n' "$excluded" | sed -n 's/^  \(.*\) — NO TAG$/\1/p' | paste -sd, -)"
if [ -n "$untagged" ]; then
  echo "report-excluded-tasks: excluded with no tag saying why: ${untagged}" >&2
  exit 1
fi

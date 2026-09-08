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

# Take the document that has `tasks`, not the first one: moon prefixes its
# stdout with an NDJSON notice when it activates a toolchain, and reading that
# as the answer reports an empty exclusion list rather than failing.
excluded="$(sed -n '/{/,$p' "$query_file" | sed '1s/^[^{]*//' | jq -r -n '
  [ inputs | select(has("tasks")) ] | first // {} | .tasks // {} | to_entries as $p
  | [ $p[] | .value | to_entries[] | .value
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

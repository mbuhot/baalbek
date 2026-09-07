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

text="$(jq -r '
  # moon reports a duration as {secs, nanos}; render it to one decimal place.
  def secs: if . == null then 0 else (.secs // 0) + ((.nanos // 0) / 1000000000) end;
  def fmt: (. * 10 | round) as $t | "\($t / 10 | floor).\($t % 10)";
  def optypes: [ (.operations // [])[] | .meta.type? ];

  [ (.actions // [])[] | select(.label | startswith("RunTask(")) ] as $tasks
  | [ $tasks[] | select(optypes | index("task-execution")) ] as $executed
  | ($executed | map(.label)) as $ran
  # Replayed means hydrated from the cache without executing.
  | [ $tasks[] | select((optypes | index("output-hydration")) and (.label as $l | $ran | index($l) | not)) ] as $replayed
  | [ $tasks[] | select(.status == "skipped") ] as $skipped
  | [ $tasks[] | select(.status == "failed" or .status == "aborted" or .status == "timed-out") ] as $failed
  # Fully parenthesised: `as` binds looser than `//`, so without these jq
  # reads the rest of the program as the right-hand side of the last `//`.
  | ((((.context // {}).affected // {}).projects) // {}) as $projects

  | [ "**moon ci:** \(.status // "unknown") in \(.duration | secs | fmt)s", "",
      "- **\($executed | length)** tasks executed",
      "- **\($replayed | length)** replayed from cache",
      "- **\($skipped | length)** skipped" ]
  + (if ($failed | length) > 0
     then [ "- **\($failed | length)** failed: \($failed | map(.label) | join(", "))" ]
     else [] end)
  + (if ($projects | length) > 0
     then [ "", "Affected by the changed files:", "" ]
          + [ $projects | to_entries | sort_by(.key)[]
              | "- `\(.key)` — \(((.value.tasks // []) | join(", ")) | if . == "" then "(no tasks)" else . end)",
                (((.value.files // [])[0:5])[] | "  - `\(.)`") ]
     else [ "", "No project was reported affected by the changed files." ] end)
  + (if ($executed | length) > 0
     then [ "", "Slowest executed tasks:", "" ]
          + [ $executed | sort_by(.duration | secs) | reverse | .[0:8][]
              | "- `\(.label | ltrimstr("RunTask(") | rtrimstr(")"))` \(.duration | secs | fmt)s" ]
     else [] end)
  | .[]
' "${REPORT}")"

printf '%s\n' "$text"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n\n' "$text" >> "${GITHUB_STEP_SUMMARY}"
fi

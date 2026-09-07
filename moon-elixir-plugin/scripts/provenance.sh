#!/usr/bin/env bash
# Records which source the committed WASM artifact was built from, and checks it.
#
# `check` fails unless the recording exists and matches both the current source
# and the committed artifact. `accept` rewrites the recording, and the artifact
# when its bytes moved.
set -euo pipefail

ARTIFACT="plugin/moon_elixir_plugin.wasm"
FRESH="${ARTIFACT}.new"
RECORD="plugin/moon_elixir_plugin.provenance"

# Every path the fingerprint walks, and it must stay equal to the build task's
# own `inputs` in ../moon.yml, which says so too. A declared input left out of
# this list lets a stale artifact pass, so the two move together. Reading the
# list from moon instead was tried and reverted; adr-0002 records why.
SOURCE_PATHS=(Cargo.toml Cargo.lock src scripts)

REBUILD="Rebuild and record it with: bash scripts/build.sh --accept"

fail() {
  printf '%s\n' "$@" >&2
  exit 1
}

# One digest over the name and content of every fingerprinted file.
source_digest() {
  local path
  for path in "${SOURCE_PATHS[@]}"; do
    [ -e "$path" ] ||
      fail "moon-elixir-plugin: ${path} is declared as an input but is missing."
  done
  find "${SOURCE_PATHS[@]}" -type f -print0 |
    LC_ALL=C sort -z |
    xargs -0 sha256sum |
    sha256sum |
    cut -d' ' -f1
}

digest_of() {
  sha256sum "$1" | cut -d' ' -f1
}

# The recorded digest for one key, or empty when the record cannot be trusted.
recorded() {
  awk -v key="$1" '$1 == key && length($2) == 64 { print $2 }' "$RECORD"
}

# Where two artifacts diverge, and which toolchain built the fresh one.
divergence() {
  cmp -s "$ARTIFACT" "$FRESH" && return 0
  rustc -vV | grep -E '^(release|host):' | sed 's/^/  rustc /'
  echo "  committed: $(wc -c < "$ARTIFACT") bytes, freshly built: $(wc -c < "$FRESH") bytes"
  # cmp reports either a differing byte or an EOF; print whichever it found.
  cmp "$ARTIFACT" "$FRESH" 2>&1 | sed -e 's/^cmp: //' -e 's/^/  /'
}

source_now="$(source_digest)"

if [ "${1:?usage: provenance.sh check|accept}" = "accept" ]; then
  if ! cmp -s "$ARTIFACT" "$FRESH"; then
    cp "$FRESH" "$ARTIFACT"
    echo "moon-elixir-plugin: replaced ${ARTIFACT} with the fresh build."
  fi
  printf 'source %s\nartifact %s\n' "$source_now" "$(digest_of "$ARTIFACT")" > "$RECORD"
  echo "moon-elixir-plugin: recorded ${RECORD}. Commit it with the artifact."
  exit 0
fi

[ -f "$RECORD" ] ||
  fail "moon-elixir-plugin: ${RECORD} is missing, so the committed" \
       "${ARTIFACT} has no recorded provenance." "$REBUILD"

source_was="$(recorded source)"
artifact_was="$(recorded artifact)"
[ -n "$source_was" ] && [ -n "$artifact_was" ] ||
  fail "moon-elixir-plugin: ${RECORD} is not readable as provenance." "$REBUILD"

artifact_now="$(digest_of "$ARTIFACT")"
if [ "$artifact_was" != "$artifact_now" ]; then
  fail "moon-elixir-plugin: ${ARTIFACT} is not the artifact ${RECORD} records." \
       "  recorded: ${artifact_was}" "  on disk:  ${artifact_now}" \
       "Either restore it, or rebuild and record it with:" \
       "  bash scripts/build.sh --accept"
fi

if [ "$source_was" != "$source_now" ]; then
  fail "moon-elixir-plugin: the committed ${ARTIFACT} was not built from" \
       "this source." "  recorded source: ${source_was}" \
       "  this source:     ${source_now}" "$(divergence)" "$REBUILD"
fi

# Reached only when the source matches: the bytes are then allowed to differ,
# because the same rustc emits different wasm from an x86_64 host than from an
# aarch64 one (adr-0002).
divergence | sed 's/^/note:/' >&2
echo "moon-elixir-plugin: ${ARTIFACT} was built from this source."

#!/usr/bin/env bash
# `mobile:build-ios` (PLAN.md Stage 7, tagged `requires-macos`): real
# xcodebuild of the Capacitor iOS project (Debug, iphonesimulator SDK,
# unsigned). Only runs on macOS — `xcodebuild` doesn't exist elsewhere.
# A separate script for the same reason as build-android.sh: moon's
# static `$VAR` pre-substitution in inline `args` strings is not safe for
# a script that exports and re-reads its own variables.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Off macOS this exits 0 with an explicit skip line, so workspace-wide
# sweeps (`moon check --all`) stay green — PLAN.md's one accepted
# exception ("iOS builds need macOS"). The skip is always logged, never
# silent, and the real xcodebuild below is unchanged: on a Mac this guard
# passes and the genuine build runs.
if [ "$(uname -s)" != "Darwin" ] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "skipped: requires-macos, not available in this environment (xcodebuild not found)"
  exit 0
fi

pnpm install --frozen-lockfile
npx cap sync ios

xcodebuild -project ios/App/App.xcodeproj -scheme App \
  -configuration Debug -sdk iphonesimulator \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build

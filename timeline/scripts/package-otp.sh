#!/usr/bin/env bash
# Moon task body for timeline:package. Builds build/otp/ — timeline and its
# runtime dependencies as ordinary OTP application directories, the form
# `timeline_facade`'s mix.exs consumes as Mix path dependencies. See
# ../../server/spec/decisions/adr-0001-release-assembly-and-gleam-packaging.md.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=timeline/scripts/toolchain-path.sh
source scripts/toolchain-path.sh

# The dev build (`gleam build`) writes {modules, []} into every .app file it
# generates; the shipment export writes the real list. Only the latter can
# back a release boot script.
gleam export erlang-shipment

# The export also copies dev-only packages (gleeunit, and the Elixir-target
# packages it drags in). Keep only timeline's runtime closure.
apps="$(escript scripts/otp-closure.escript build/erlang-shipment timeline)"

rm -rf build/otp
mkdir -p build/otp
# tar, not cp: cp -R across this repo's virtiofs mount has been observed
# writing a NUL-filled file of the right length instead of the contents.
for app in $apps; do
  tar -C build/erlang-shipment -cf - "$app" | tar -C build/otp -xf -
done

# The copied tree is what Mix reads, so re-check it rather than the source.
escript scripts/otp-closure.escript build/otp timeline >/dev/null

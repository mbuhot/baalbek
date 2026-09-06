#!/usr/bin/env bash
# Moon task body for timeline:bootstrap.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=timeline/scripts/toolchain-path.sh
source scripts/toolchain-path.sh

gleam run -m timeline/bootstrap

#!/usr/bin/env bash
# Runs a command inside this repository's own sandbox/CI image.
#
#   .github/scripts/run-in-sandbox.sh moon ci
#
# .github/workflows/image-gate.yml runs the whole graph through it, and a
# developer can use it to reproduce a failure locally. Several flags below are
# load-bearing rather than conventional, and so is the separate Moon cache;
# adr-0007 covers each, and adr-0009 covers where CI calls this.
set -euo pipefail

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
IMAGE="${SANDBOX_IMAGE:-baalbek-sandbox:latest}"
# Toolchain downloads that are not Moon task outputs: Playwright's browsers,
# the Android SDK, the Cargo registry, hex's package cache, Gradle's dependency
# cache, the redirected Cargo target directories. Kept outside the workspace so
# CI can cache them between runs without ever caching a task output.
CACHE_ROOT="${SANDBOX_CACHE_ROOT:-${HOME}/.cache/baalbek-sandbox}"
# Moon's task cache, and deliberately NOT under CACHE_ROOT: nothing may restore
# it between runs. Moon's hashes are environment-independent — the same task
# hashes identically inside and outside this image — so a shared cache lets the
# container replay hits the host produced, and the run proves nothing about
# whether the image can actually do the work. That is the stale-hit failure
# PLAN.md's hermeticity posture exists to prevent, and it is what hid a broken
# task from this script's first outing.
MOON_CACHE_DIR="${SANDBOX_MOON_CACHE:-/tmp/baalbek-sandbox-moon-cache}"

if [ "$#" -eq 0 ]; then
  echo "usage: $(basename "$0") <command> [args...]" >&2
  exit 2
fi

# Named rather than left to `docker run`, which would try to pull it and report
# a registry authentication failure instead.
if ! docker image inspect "${IMAGE}" > /dev/null 2>&1; then
  echo "${IMAGE} is not in the local docker daemon." >&2
  echo "Get it with: .github/scripts/resolve-sandbox-image.sh" >&2
  exit 1
fi

mkdir -p \
  "${CACHE_ROOT}/cache" \
  "${CACHE_ROOT}/android-sdk" \
  "${CACHE_ROOT}/cargo-registry" \
  "${CACHE_ROOT}/hex" \
  "${MOON_CACHE_DIR}"

# A build run on the host can leave symlinks into the host's $HOME in the
# working tree — `timeline/build/dev/erlang/elixir` points into $PROTO_HOME, for
# one — and those dangle in here, where $HOME is /home/vscode. CI never sees it,
# because a fresh checkout has no build trees. Warned about rather than fixed:
# deleting another tool's build output is not this script's call.
host_link="$(find "${WORKSPACE}" -type l -lname "${HOME}/*" -not -path "*/node_modules/*" -print -quit 2>/dev/null || true)"
if [ -n "${host_link}" ]; then
  echo "warning: this working tree has host-built output symlinked into ${HOME}, starting with" >&2
  echo "warning:   ${host_link}" >&2
  echo "warning: those links dangle inside the container, so tasks that read them will fail in ways CI will not." >&2
  echo "warning: delete the build tree they belong to for a faithful run." >&2
fi

# Mounted at whatever `.moon/cache` resolves to, which is the workspace path in
# CI and somewhere off the working tree wherever that tree is a bind mount — a
# named volume in the devcontainer, a symlink in an agent sandbox. Resolving it
# covers both, and the mount keeps the host's cache out and stops a symlink
# dangling in here.
MOON_CACHE_TARGET="$(readlink -f "${WORKSPACE}/.moon/cache")"

# The image runs as `vscode`, uid 1000. Every host path mounted below has to be
# writable by that uid; on a GitHub runner the checkout is uid 1001, which the
# workflow chowns before calling this.
docker run --rm --init \
  --user vscode \
  --group-add "$(stat -c '%g' /var/run/docker.sock)" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --network host \
  -v "${WORKSPACE}:${WORKSPACE}" \
  -w "${WORKSPACE}" \
  -v "${CACHE_ROOT}/cache:/home/vscode/.cache" \
  -v "${CACHE_ROOT}/android-sdk:/home/vscode/.android-sdk" \
  -v "${CACHE_ROOT}/cargo-registry:/home/vscode/.cargo/registry" \
  -v "${CACHE_ROOT}/hex:/home/vscode/.hex" \
  -v "${MOON_CACHE_DIR}:${MOON_CACHE_TARGET}" \
  -e CI \
  -e MOON_BASE \
  -e MOON_HEAD \
  -e MOON_LOG \
  -e SANDBOX_IMAGE \
  -e SERVER_IMAGE \
  -e WEB_IMAGE \
  -e E2E_BASE_URL \
  -e E2E_HOST_PORT \
  -e MOBILE_API_BASE_URL \
  "${IMAGE}" \
  bash -lc 'exec "$@"' run-in-sandbox "$@"

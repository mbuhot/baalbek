#!/usr/bin/env bash
# Bind-mounts every directory the build writes into onto local storage, off the
# bind mount that carries the working tree.
#
#   scripts/mount-build-dirs.sh setup | check | teardown | list | check-devcontainer
#
# The devcontainer mounts a named volume over each one instead, and
# `check-devcontainer` fails when the two lists disagree. See
# ../spec/decisions/adr-0013-build-output-lives-off-the-working-tree.md.

set -euo pipefail

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${WORKSPACE}"
STORE="${BAALBEK_BUILD_DIRS:-${HOME}/.cache/baalbek/build-dirs}"

# Every directory a tool owns, found from the manifest that declares the tool.
# `git ls-files` rather than `find`: a find would match the thousands of
# manifests inside deps/ and node_modules/, and the plugin's fixture projects
# under tests/ are parsed, never built.
tool_dirs() {
  local manifest dir
  while IFS= read -r manifest; do
    dir="$(dirname "${manifest}")"
    [ "${dir}" = "." ] && dir=""
    case "$(basename "${manifest}")" in
      # `build/` is this repository's own convention for an Elixir project's
      # declared artefact, beside Mix's `_build/` and `deps/`.
      mix.exs)      printf '%s\n' "${dir}/_build" "${dir}/deps" "${dir}/build" ;;
      gleam.toml)   printf '%s\n' "${dir}/build" ;;
      Cargo.toml)   printf '%s\n' "${dir}/target" ;;
      package.json) printf '%s\n' "${dir:-.}/node_modules" ;;
    esac
  done < <(git ls-files |
    grep -E '(^|/)(mix\.exs|gleam\.toml|Cargo\.toml|package\.json)$' |
    grep -v '^moon-elixir-plugin/tests/__fixtures__/')
}

# The rest, each following no tool convention. The Gradle ones cover a plain
# `gradlew` run: mobile/moon.yml already sends the task's own output to $HOME.
other_dirs() {
  printf '%s\n' .moon/cache .pnpm-store .artifacts node_modules \
    pricing/build e2e/build explorer/dist web/dist \
    mobile/android/build mobile/android/app/build mobile/ios/build
}

# Refuses any path holding tracked files: a mount over one would hide source.
build_dirs() {
  local dir
  while IFS= read -r dir; do
    dir="${dir#./}"
    if [ -n "$(git ls-files -- "${dir}")" ]; then
      echo "mount-build-dirs: ${dir} holds tracked files; refusing to mount over it" >&2
      exit 1
    fi
    printf '%s\n' "${dir}"
  done < <({ tool_dirs; other_dirs; } | sed 's#^\./##' | LC_ALL=C sort -u)
}

mounted() {
  findmnt --noheadings --mountpoint "${WORKSPACE}/$1" > /dev/null 2>&1
}

require_sudo() {
  sudo -n true 2> /dev/null && return 0
  echo "mount-build-dirs: needs sudo to bind-mount. The devcontainer does not:" >&2
  echo "mount-build-dirs: it mounts a named volume over each of these instead." >&2
  exit 1
}

case "${1:?usage: mount-build-dirs.sh setup|check|teardown|list|check-devcontainer}" in
  list)
    build_dirs
    ;;
  check-devcontainer)
    # The devcontainer's list is hand-written YAML, and nothing compared it
    # against this one until server/build had been missing from it for a while.
    compose=".devcontainer/docker-compose.yml"
    declared="$(sed -nE 's#^ +- [a-z0-9-]+:/workspaces/baalbek/(.+)$#\1#p' "${compose}" |
      LC_ALL=C sort -u)"
    report="$(mktemp)"
    trap 'rm -f "${report}"' EXIT
    if ! diff <(build_dirs) <(printf '%s\n' "${declared}") > "${report}"; then
      echo "mount-build-dirs: ${compose} does not mount every build directory." >&2
      sed -nE -e 's/^< /  missing a volume: /p' \
        -e 's/^> /  volume for no build directory: /p' "${report}" >&2
      exit 1
    fi
    echo "mount-build-dirs: ${compose} mounts all $(build_dirs | wc -l) build directories"
    ;;
  setup)
    require_sudo
    while IFS= read -r dir; do
      mounted "${dir}" && continue
      mkdir -p "${STORE}/${dir}" "${dir}"
      # Content already in the tree moves to the store, so the first build
      # after setup is not a cold one.
      if [ -n "$(ls -A "${dir}")" ] && [ -z "$(ls -A "${STORE}/${dir}")" ]; then
        (shopt -s dotglob nullglob; mv "${dir}"/* "${STORE}/${dir}/")
      fi
      sudo mount --bind "${STORE}/${dir}" "${dir}"
      echo "mounted ${dir}"
    done < <(build_dirs)
    ;;
  check)
    missing=0
    while IFS= read -r dir; do
      mounted "${dir}" || { echo "not mounted: ${dir}" >&2; missing=1; }
    done < <(build_dirs)
    if [ "${missing}" = 1 ]; then
      echo "mount-build-dirs: run scripts/mount-build-dirs.sh setup" >&2
      exit 1
    fi
    echo "mount-build-dirs: every build directory is on ${STORE}"
    ;;
  teardown)
    require_sudo
    while IFS= read -r dir; do
      if mounted "${dir}"; then
        sudo umount "${WORKSPACE}/${dir}"
        echo "unmounted ${dir}"
      fi
    done < <(build_dirs | tac)
    ;;
  *)
    echo "usage: mount-build-dirs.sh setup|check|teardown|list|check-devcontainer" >&2
    exit 2
    ;;
esac

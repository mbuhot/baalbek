#!/usr/bin/env bash
# Installs the OS packages the sandbox image needs, for the image and for a CI
# runner alike. The Dockerfile runs one group per layer; the runner runs `all`.
#
#   scripts/install-os-deps.sh <toolchain|tasks|all>
#
# See spec/decisions/adr-0009-where-ci-runs-moon-ci.md.
set -euo pipefail

# An alternative is written `preferred|fallback`, for Ubuntu's t64 renames.
# Compilers and fetch tools, then Erlang/OTP's own build dependencies.
TOOLCHAIN_PACKAGES=(
  build-essential
  git
  curl
  wget
  ca-certificates
  gnupg
  lsb-release
  pkg-config
  unzip
  xz-utils
  file
  locales

  autoconf
  m4
  libncurses-dev
  libssl-dev
  unixodbc-dev
  libsctp-dev
  zlib1g-dev
)

# From PGDG: Debian bookworm's own repositories stop at the Postgres 15 client.
TOOLCHAIN_PGDG_PACKAGES=(
  postgresql-client-17
  libpq-dev
)

# jq parses `moon query` output and moon's own CI report; the rest is
# playwright-core 1.63.0's own `debian12` chromium set, plus fontconfig and
# one font family.
TASK_PACKAGES=(
  jq
  "libasound2t64|libasound2"
  "libatk-bridge2.0-0t64|libatk-bridge2.0-0"
  "libatk1.0-0t64|libatk1.0-0"
  "libatspi2.0-0t64|libatspi2.0-0"
  libcairo2
  "libcups2t64|libcups2"
  libdbus-1-3
  libdrm2
  libgbm1
  "libglib2.0-0t64|libglib2.0-0"
  libnspr4
  libnss3
  "libpango-1.0-0|libpango1.0-0"
  libx11-6
  libxcb1
  libxcomposite1
  libxdamage1
  libxext6
  libxfixes3
  libxkbcommon0
  libxrandr2
  fontconfig
  fonts-liberation
)

# Buildx is not optional: without it `docker build` degrades to the legacy
# builder, which shares no cache with the daemon's BuildKit.
TASK_DOCKER_PACKAGES=(
  docker-ce-cli
  docker-buildx-plugin
  docker-compose-plugin
)

if [ "$#" -ne 1 ]; then
  echo "usage: $(basename "$0") <toolchain|tasks|all>" >&2
  exit 2
fi
GROUP="$1"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID:?/etc/os-release has no ID}"
DISTRO_CODENAME="${VERSION_CODENAME:?/etc/os-release has no VERSION_CODENAME}"

export DEBIAN_FRONTEND=noninteractive

add_pgdg_repo() {
  ${SUDO} install -d /usr/share/postgresql-common/pgdg
  ${SUDO} curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${DISTRO_CODENAME}-pgdg main" |
    ${SUDO} tee /etc/apt/sources.list.d/pgdg.list > /dev/null
}

add_docker_repo() {
  ${SUDO} install -d -m 0755 /etc/apt/keyrings
  ${SUDO} curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" \
    -o /etc/apt/keyrings/docker.asc
  ${SUDO} chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${DISTRO_CODENAME} stable" |
    ${SUDO} tee /etc/apt/sources.list.d/docker.list > /dev/null
}

# Resolves each `preferred|fallback` spec against the apt index, into RESOLVED.
# A global, not stdout: a `return` from a process substitution cannot fail the
# caller, and a truncated package list must not install silently.
RESOLVED=()

resolve_packages() {
  local spec name found shown
  RESOLVED=()
  for spec in "$@"; do
    found=""
    while IFS= read -r name; do
      # Captured whole: `apt-cache show | grep -q` races on SIGPIPE.
      if shown="$(apt-cache show "${name}" 2> /dev/null)" && [ -n "${shown}" ]; then
        found="${name}"
        break
      fi
    done < <(printf '%s\n' "${spec//|/$'\n'}")
    if [ -z "${found}" ]; then
      echo "install-os-deps: no package in '${spec}' exists on ${DISTRO_ID} ${DISTRO_CODENAME}" >&2
      return 1
    fi
    RESOLVED+=("${found}")
  done
}

install_packages() {
  resolve_packages "$@"
  ${SUDO} apt-get install -y --no-install-recommends "${RESOLVED[@]}"
}

# Each extra repository is added after the first pass: the slim base has no
# curl to fetch a signing key with until then.
case "${GROUP}" in
  toolchain)
    ${SUDO} apt-get update
    install_packages "${TOOLCHAIN_PACKAGES[@]}"
    add_pgdg_repo
    ${SUDO} apt-get update
    install_packages "${TOOLCHAIN_PGDG_PACKAGES[@]}"
    ;;
  tasks)
    ${SUDO} apt-get update
    install_packages "${TASK_PACKAGES[@]}"
    add_docker_repo
    ${SUDO} apt-get update
    install_packages "${TASK_DOCKER_PACKAGES[@]}"
    ;;
  all)
    ${SUDO} apt-get update
    install_packages "${TOOLCHAIN_PACKAGES[@]}" "${TASK_PACKAGES[@]}"
    add_pgdg_repo
    add_docker_repo
    ${SUDO} apt-get update
    install_packages "${TOOLCHAIN_PGDG_PACKAGES[@]}" "${TASK_DOCKER_PACKAGES[@]}"
    ;;
  *)
    echo "install-os-deps: unknown group '${GROUP}'" >&2
    exit 2
    ;;
esac

${SUDO} rm -rf /var/lib/apt/lists/*

#!/usr/bin/env bash
# Prints the sandbox image's content tag, a digest of every input to that image
# plus the architecture it is built for.
#
# The file list must match `root:sandbox-image`'s `inputs:` in moon.yml, and the
# arch has to be the daemon's rather than the client's, because the daemon is
# what builds. An amd64 image cannot supply a layer to an arm64 build, so
# without the arch the tag would claim a match it cannot deliver. See
# spec/decisions/adr-0008-the-sandbox-image-is-published-to-ghcr.md.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

INPUTS=(Dockerfile .dockerignore .prototools)

for input in "${INPUTS[@]}"; do
  if [ ! -f "${input}" ]; then
    echo "sandbox-image-tag: '${input}' is not a file in $(pwd)" >&2
    exit 1
  fi
done

# Failing beats guessing: a wrong arch here is a tag that lies.
if ! arch="$(docker version --format '{{.Server.Arch}}' 2>/dev/null)" || [ -z "${arch}" ]; then
  echo "sandbox-image-tag: no docker daemon to read the target architecture from" >&2
  exit 1
fi

# Hashes each path with its content, so moving a byte between two inputs still
# moves the tag. The array order fixes the digest.
digest="$(sha256sum "${INPUTS[@]}" | sha256sum | cut -c1-16)"

echo "toolchain-${arch}-${digest}"

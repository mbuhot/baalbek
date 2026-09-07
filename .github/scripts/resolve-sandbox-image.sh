#!/usr/bin/env bash
# Puts the sandbox image in the local docker daemon, reusing the published
# image's layers when one was built from this tree's inputs.
#
# It always builds the current Dockerfile and uses the registry only as a cache
# source, so the image can never be older than the tree. Which of the three
# paths ran is printed as a banner, because a cache that quietly stopped working
# looks exactly like CI getting slower for no reason. See
# spec/decisions/adr-0008-the-sandbox-image-is-published-to-ghcr.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WORKSPACE="$(cd "${HERE}/../.." && pwd -P)"
cd "${WORKSPACE}"

# The same hook run-in-sandbox.sh and `root:sandbox-image` read.
IMAGE="${SANDBOX_IMAGE:-baalbek-sandbox:latest}"
TAG="$("${HERE}/sandbox-image-tag.sh")"

# CI passes the owner; a developer's clone falls back to its own origin remote.
owner="${GITHUB_REPOSITORY_OWNER:-}"
if [ -z "${owner}" ]; then
  owner="$(git config --get remote.origin.url 2>/dev/null |
    sed -nE 's#.*github\.com[:/]([^/]+)/.*#\1#p')"
fi
if [ -n "${owner}" ]; then
  owner="$(printf '%s' "${owner}" | tr '[:upper:]' '[:lower:]')"
fi
REPO="${SANDBOX_IMAGE_REPO:-${owner:+ghcr.io/${owner}/baalbek-sandbox}}"
# `none` rather than an empty value, so a workflow can pass an unset GitHub
# variable through without that reading as "never touch a registry".
if [ "${REPO}" = "none" ]; then
  REPO=""
fi

announce() {
  echo "=================================================================="
  echo "sandbox image: $*"
  echo "=================================================================="
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '**sandbox image:** %s\n\n' "$*" >> "${GITHUB_STEP_SUMMARY}"
  fi
}

# An exact tag means byte-identical inputs. `:latest` is a partial source: every
# layer below the first difference still hits.
cache_ref=""
exact=""
if [ -z "${REPO}" ]; then
  announce "NO REGISTRY resolved, building ${IMAGE} from source"
else
  echo "sandbox image: this tree's inputs digest to ${TAG}"
  for candidate in "${REPO}:${TAG}" "${REPO}:latest"; do
    # The probe's own message is the only thing that separates a 401 from an
    # unreachable registry from a tag that was never published.
    if probe_error="$(docker buildx imagetools inspect "${candidate}" 2>&1 > /dev/null)"; then
      cache_ref="${candidate}"
      break
    fi
    echo "sandbox image: cannot use ${candidate}"
    if [ -n "${probe_error}" ]; then
      echo "sandbox image:   ${probe_error}"
    fi
  done

  if [ "${cache_ref}" = "${REPO}:${TAG}" ]; then
    exact="yes"
    announce "CACHE HIT on ${cache_ref}, every layer should be reused"
  elif [ -n "${cache_ref}" ]; then
    announce "PARTIAL CACHE on ${cache_ref}: no image matches ${TAG}, so this tree's Dockerfile or architecture differs from the published one and Erlang/OTP may recompile"
  else
    announce "COLD, no cache source resolved from ${REPO} for ${TAG}; the probe output above says why, and it is not always an absent image"
  fi
fi

# `--builder default` pins the daemon's own BuildKit, which is the one cache
# `root:sandbox-image` later reads. A `docker-container` builder would import
# the image and leave that cache cold.
args=(--builder default --load --tag "${IMAGE}" --file Dockerfile)
if [ -n "${cache_ref}" ]; then
  # A missing or unreachable ref only warns and exits 0, hence the check below.
  args+=(--cache-from "type=registry,ref=${cache_ref}")
fi

started="${SECONDS}"
docker buildx build "${args[@]}" .
elapsed="$((SECONDS - started))"

echo "sandbox image: ${IMAGE} ready in ${elapsed}s"

# 120s is a guess, not a measurement: transferring the image's layers could
# legitimately exceed it. So this asks rather than concludes.
if [ -n "${exact}" ] && [ "${elapsed}" -gt 120 ]; then
  announce "WARNING: ${cache_ref} matched but the build took ${elapsed}s; check whether its layers were reused"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf 'Built %s in %ss.\n\n' "${IMAGE}" "${elapsed}" >> "${GITHUB_STEP_SUMMARY}"
fi

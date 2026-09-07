#!/usr/bin/env bash
# Hands the workspace's named volumes to `vscode`, then execs the container's command.
#
# Docker creates a fresh named volume's mount point owned by root, and the
# sandbox image ships no sudo, so the build-artifact volumes in
# docker-compose.yml would otherwise be unwritable by the remote user. The
# mount table is read rather than the volume list repeated, so the two cannot
# drift; the repository's own mount point is excluded because it is the host
# bind mount. A volume whose path is a symlink out of the tree is not seen —
# Docker resolves the link and mounts at the target instead.
set -euo pipefail

awk '$5 ~ /^\/workspaces\/baalbek\// { print $5 }' /proc/self/mountinfo |
  while read -r mount_point; do
    chown vscode:vscode "$mount_point"
  done

exec "$@"

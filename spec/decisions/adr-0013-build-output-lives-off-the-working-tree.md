# ADR-0013: Build output lives off the working tree, by moving the storage under it

**Status:** Accepted
**Date:** 2026-09-07
**Stage:** post-Stage 12, during the moon.yml simplification pass

## Context

The working tree reaches a Linux container over a bind mount, and on macOS and
Windows that mount is the slowest filesystem in the build. It exists so the
source can be edited and watched on the host; nothing wants the 1.4 GB of
build output that had accumulated beside it.

## Decision

Every directory the build writes into is placed on local storage, at its
existing in-tree path. The path does not move; the storage moves under it.

- The devcontainer mounts a named volume over each one
  (`.devcontainer/docker-compose.yml`).
- Everywhere else, `scripts/mount-build-dirs.sh setup` bind-mounts each one
  from `$HOME/.cache/baalbek/build-dirs`.
- The list is derived, not written down: `mix.exs` implies `_build`, `deps`
  and `build`; `gleam.toml` and this repository's own convention imply
  `build`; `Cargo.toml` implies `target`; `package.json` implies
  `node_modules`. Eleven more follow no tool convention and are named
  explicitly.
- `check-devcontainer` compares the derived list against the hand-written
  YAML, and `root:test` runs it.

## Why the paths cannot simply move

Moon requires a task's `outputs` to live inside its project, and adr-0006 has
this repository declare `deps/` and `<project>/build/` as outputs so a
consumer can hydrate a producer's tree from the cache. Redirecting them with
`MIX_DEPS_PATH` or `MIX_BUILD_PATH` would put them where no `outputs` glob can
name them, which costs the cross-project cache that adr-0006 exists to
provide. `CARGO_TARGET_DIR`, Gradle's build directory and Playwright's output
directory *are* redirected by configuration, and that is precisely because
nothing declares them as an output.

## Alternatives rejected

**Symlink each directory into the store.** Survives a reboot and needs no
sudo. Rejected because the links are visible in the working tree: an absolute
target under `$HOME` resolves to a different place inside the sandbox image
than on the host, which is the dangling-symlink case
`.github/scripts/run-in-sandbox.sh` already warns about.

**Clone the repository into a volume**, as the devcontainer comment suggests.
This removes the whole problem and the whole directory list with it, at the
cost of no working tree on the host — which is the one thing the bind mount is
for.

**Leave it to each environment.** The devcontainer already had 37 of the 38
volumes, and the one it lacked, `server/build`, held 128 MB. A
hand-maintained list in one environment and nothing in the others is how that
happened.

## Consequences accepted

- **The bind-mounted mode needs sudo, and does not survive a reboot.**
  `setup` runs again afterwards; `check` says whether it is needed.
- **A missing mount is silent.** The build still works, just on the slow
  filesystem. `check` is the only thing that reports it, and nothing runs
  `check` automatically, because a task that failed on an unmounted tree
  would block work rather than speed it up.
- **The derivation can be wrong in one direction.** A directory following no
  tool convention has to be added by hand, exactly as before; what is now
  automatic is that the devcontainer cannot disagree with the result.

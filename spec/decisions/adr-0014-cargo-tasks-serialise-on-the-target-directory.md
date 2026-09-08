# ADR-0014: Every cargo task serialises on the shared target directory

**Status:** Accepted
**Date:** 2026-09-08
**Stage:** post-Stage 12, during the moon.yml simplification pass

## Context

`pricing`, `pricing_native` and `server` share one `CARGO_TARGET_DIR`, so one
compile of the `pricing` crate serves all three. Every Elixir app that takes
`pricing_native` as a Mix path dependency also rebuilds its Rustler NIF,
because a Mix path dep compiles into the *parent's* build path — and `server`
has three of those, one per `MIX_ENV`.

Those build trees are isolated, and that is not where they collide: each holds
its own real `ebin`. But Mix does not copy a dependency's `priv/`, it symlinks
it back to the dependency's source directory, so
`server/build/dev/lib/pricing_native/priv` and
`pricing_native/build/test/lib/pricing_native/priv` both resolve to
`pricing_native/priv`. Every one of those separate compiles therefore writes
its NIF to the same single file, and reads and writes the same cargo target
directory. Two shared resources, neither of them a build tree.

Two of those tasks have no ordering between them. `server:build` does depend
on `pricing_native:build`, but `pricing_native:test` depends only on
`pricing:build` and `pricing_native:deps`, so moon may schedule it alongside
any of `server`'s compiles. Both then run cargo against the same target
directory and both write `pricing_native/priv/native/pricingnative.so`.

That fails intermittently:

```
server:build | Blocking waiting for file lock on package cache
server:build | == Compilation error in file lib/pricing_native/native.ex ==
server:build | ** (File.CopyError) could not copy from
  ".../baalbek-cargo-target/release/libpricingnative.so"
  to "priv/native/pricingnative.so": no such file or directory
```

The missing file is cargo's own artifact, not the destination. One cargo
finishes, Rustler is about to copy the result, and the other cargo — released
from the lock — unlinks that artifact to rebuild it. Reproduced directly, two
concurrent compiles at a time: **2 failures in 6**, with both processes
confirmed to have reached Rustler's copy step in 6 of 6. Either side can lose;
the original sighting had `server` fail, the reproduction had `pricing_native`.

## Decision

Every task that runs cargo against that directory carries
`options: { mutex: "cargo-target-dir" }`: `pricing:build`, `pricing:test`,
`pricing_native:build`, `pricing_native:test`, and `server`'s `build`,
`test`, `bootstrap`, `openapi` and `release`.

`server:deps` is excluded deliberately. It compiles only
`$MIX_THIRD_PARTY_DEPS`, and `pricing_native` is a path dependency that never
appears in `mix.lock`, so it never invokes Rustler.

## Alternatives rejected

**A `CARGO_TARGET_DIR` per project.** Closes the window on cargo's artifact
and leaves the second one open: both processes still write
`pricing_native/priv/native/pricingnative.so`, because the `priv` symlink is
Mix's doing and not ours, and `File.cp!` truncates its destination. It also
gives up the shared compile of the `pricing` crate.

**A dependency edge from `server:build` to `pricing_native:test`.** Orders the
pair that was observed, but a build depending on a test suite is backwards,
and it does not order `pricing_native:test` against `server:test`,
`server:release` or `server:bootstrap`.

**Declaring the `.so` as an output so moon serialises the writers.** adr-0006
already rejected declaring it, for the same reason it would matter here: moon
would restore a cached copy over a tree another task is writing.

## Consequences accepted

- **Rust work in this workspace is serial.** It measured free: two runs each
  way over the same four tasks gave 26.3s and 22.6s with the mutex against
  23.9s and 50.0s without. cargo's own lock already serialised the builds, so
  the mutex only moves the waiting to before a task starts, outside Rustler's
  copy window — and the 50s outlier is what that contention costs when it is
  left to cargo.
- **A new cargo task has to opt in.** Nothing detects a task that runs cargo
  and omits the mutex; the failure it reintroduces is intermittent.
- **The mutex is workspace-wide by name.** Any future project sharing this
  target directory must use the same string to be serialised against these.

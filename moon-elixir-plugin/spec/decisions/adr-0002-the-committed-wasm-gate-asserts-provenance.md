# ADR-0002: The committed WASM gate asserts provenance, not byte-identity

**Status:** Accepted.
**Date:** 2026-09-07
**Stage:** 12, from the first full-graph CI run

Supersedes the *"the compiled artifact is committed, and only the build task
catches a stale one"* consequence of
[adr-0001](adr-0001-mix-path-dep-inference.md), and specifically this claim
inside it:

> Verified alongside it: the build is reproducible. A clean rebuild in a fresh
> `CARGO_TARGET_DIR` produced a byte-identical `moon_elixir_plugin.wasm`
> (`sha256 cff79dec…`), so "does the committed artifact match the source" is a
> decidable question and the guard above is a sound way to ask it.

The question is still decidable. Byte-identity is not the way to ask it.

## Context

`plugin/moon_elixir_plugin.wasm` is committed, for the bootstrap reason
adr-0001 gives: moon loads the file while building the project graph, so
without it every moon command fails, including the one that would build it.
A committed build output can be stale, and adr-0001's mitigation was to
rebuild it in the task and compare the fresh bytes against the committed ones.

That comparison fired on the first CI run that built the plugin on a hosted
runner, on a tree whose artifact was current:

```
moon-elixir-plugin: the committed plugin/moon_elixir_plugin.wasm is not what this source builds.
- plugin/moon_elixir_plugin.wasm.new differ: byte 1271, line 4
```

Two rounds of fixes had already been aimed at path variance. The first found a
real cause: a release build bakes each `panic!` location into the artifact as
data, and for a registry dependency that is an absolute path under
`$CARGO_HOME`, which follows `$HOME`. A `--remap-path-prefix` for that prefix
made two different `$HOME` values agree. The second round assumed the crate's
own workspace path was the remaining variable, because the CI log showed
`Compiling moon_elixir_plugin v0.1.0 (/home/runner/work/baalbek/baalbek/…)`.

**That diagnosis was wrong, and measuring it is what settled this ADR.**

Byte 1271 is not a path. Walking the artifact's section table puts it at the
first byte of the *function* section's LEB128 length:

| section | body | size |
|---|---|---|
| 1 type | `[11:360]` | 349 |
| 2 import | `[363:1269]` | 906 |
| 3 function | `[1272:3235]` | 1963 |

`cmp` reports 1-based, so byte 1271 is offset 1270, and every byte before it —
the whole import section included — matched. A differing section *length*
means a different number of generated functions. It is different code, not a
different string, and no path remap can reach it.

The remaining input was found by reading the failing run's log. CI built with
`rustc 1.98.1 (48a229cea 2026-09-01)`; so does this workspace. The crate
versions cargo downloaded match the committed `Cargo.lock`. The one difference
is the host triple: `stable-x86_64-unknown-linux-gnu` on the runner against
`stable-aarch64-unknown-linux-gnu` in the sandbox.

Three controls, each a full recompile in a fresh `CARGO_TARGET_DIR`, confirm
nothing else is left. Building the crate from a copy at a longer absolute path,
under a different `$HOME`, with a different `$CARGO_HOME`, produced
`sha256 974fad1d…` every time — byte-identical to the committed artifact, and
`strings` finds no `/home/`, `/Users/` or `/tmp/` path in it at all.

So the same source, the same `Cargo.lock`, the same rustc and the same flags
produce different WASM from a different host architecture. `trim-paths` would
not have helped either; it is unstable on cargo 1.98.1 and it addresses paths.

**This repository has now had "the same source produces the same bytes"
falsified three times, in three different ways.** A `project://` input folded
another project's tree into a hash and raced a task rewriting it
(`../../spec/decisions/adr-0002-cross-language-edges-need-project-inputs.md`,
itself superseded). `$CARGO_HOME` reached into panic locations, above. And now
codegen differs across host architectures. The pattern is that byte-identity
is a proxy that holds until an environment nobody tested moves. What the gate
actually needs to know is whether the committed artifact came from the
committed source.

## Decision

### The gate records provenance

`plugin/moon_elixir_plugin.provenance` is committed next to the artifact and
holds two digests:

```
source 7db37dde1540a7629e05c5533a4e23a14296ae7ce928b3bab07ba5a33fd6bb07
artifact 974fad1d3127037950a88c331c631e7aae4add9e653920cbfb349128fceb2566
```

`source` is one SHA-256 over the name and content of every fingerprinted file.
`artifact` is the SHA-256 of the committed WASM. `scripts/provenance.py check`
fails unless both match what is on disk, so it catches a source change nobody
rebuilt for *and* an artifact swapped without a rebuild. It is host-independent,
because neither digest is a function of the compiler.

`scripts/build.sh --accept` is the only thing that writes either tracked file.
It replaces the artifact when the fresh bytes differ, always rewrites the
record, and prints what it did. A failing check leaves the tracked files
untouched, which is the property the previous guard's compare-before-rename
ordering existed to protect.

### The fingerprinted file list is restated, and the coupling is stated twice

`provenance.py` walks `Cargo.toml`, `Cargo.lock`, `src` and `scripts` — the
build task's `inputs`, minus the inherited workspace glob. `SOURCE_PATHS` and
`moon.yml`'s `inputs` are therefore two descriptions of one fact, which is the
shape adr-0001 argues against, and each names the other in a comment because
an input listed in moon.yml and not fingerprinted lets a stale artifact pass.

**Deriving the list from moon was preferred, implemented, and reverted on
measurement.** `moon task <target> --json` reports the task's inputs, and a
version of this gate read them and failed when one fell outside the walk. It
made the gate flaky. Under four concurrent `moon query projects` processes,
one run in six had the nested `moon task --json` exit 0 with a document whose
`inputs` list was *empty*, because the project graph had partially failed
(`elixir toolchain: cannot read mix.exs dependencies: elixir exited with 1`).
The fail-closed guard then failed the build for a reason that had nothing to
do with the artifact:

```
moon-elixir-plugin: the build task declares no inputs, so nothing
can be fingerprinted. Fix moon.yml before trusting this gate.
```

`moon ci` runs 48 tasks against this graph, so that is a gate which would fail
intermittently in exactly the place it is meant to be trusted — and a flaky
gate gets switched off, which is a worse outcome than the drift it prevents.
Resolving the globs locally instead was rejected for the reason adr-0001
spends most of its length on: it means re-implementing moon's glob and
`hasher.ignorePatterns` semantics, and moon 2.5.4 has no `query hash`
subcommand to read the resolved list back from.

Fingerprinting *every* file in the project directory was also considered,
which would make coverage structural rather than checked — the shape
`../../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md` argues
for. Rejected on friction: editing this README or an ADR in this directory
would then fail the build task until the record was rewritten, and `target/`
exists on a developer's machine and not on a fresh checkout, so the walk would
need an exclusion list that is itself environment-dependent.

The inherited workspace input (`/.moon/*.{yml,yaml,…}`) is deliberately
outside the fingerprint. The crate is standalone by adr-0001's second
decision, so only its own files can change its artifact, and including
workspace config would churn the record on unrelated edits.

### `moon-elixir-plugin:test` remains the behavioural proof

Provenance says the artifact came from this source. It does not say the
artifact works. `moon-elixir-plugin:test` does: it takes a `deps` on `~:build`
and drives the compiled `wasm32-wasip1` artifact through moon's plugin test
harness against a real `elixir` subprocess. That pairing is what makes the
weaker freshness property sufficient — a record can only ever attest to
provenance, and the suite is what refuses a broken artifact.

## Consequences accepted

- **The gate no longer proves the committed bytes are what this compiler
  builds, and cannot.** Byte-equality also caught an artifact built from this
  source by a *different* toolchain — a stale rustc, a hand-edited profile, a
  `cargo build` with different flags. That is now invisible to the gate.
  `moon-elixir-plugin:test` still exercises whatever bytes are committed, so a
  broken artifact fails; a merely differently-compiled one passes. Accepted
  because the alternative is a gate that cannot pass in CI at all.
- **A byte difference is now reported, not failed.** When the source matches
  and the bytes do not, the task prints the divergence and exits 0:

  ```
  note:  rustc host: aarch64-unknown-linux-gnu
  note:  rustc release: 1.98.1
  note:  committed: 1360526 bytes, freshly built: 1360526 bytes
  note:  first difference at byte 1270: the "function" section's declared length
  ```

  That is the information which distinguishes "somebody forgot to rebuild"
  from "the toolchain moved", and it is worth keeping precisely because the
  finding above took a section-table walk and a CI-log read to reach. It is a
  note nobody is forced to read, which is the weakness of every non-failing
  signal.
- **`scripts/**/*` is inside the fingerprint, so editing the build script
  needs `--accept`.** The build flags live there and genuinely change the
  artifact, so covering them is right, but it means a comment-only edit to
  `build.sh` fails the gate until the record is rewritten. `--accept` only
  replaces the artifact when the bytes actually moved, so this costs a
  65-byte record rather than a new 1.3 MB blob in git history.
- **`build.sh` no longer needs git, and needs no moon.** The old guard read the
  committed bytes with `git show`; the record is a file, so the check reads the
  working tree and nothing else. `bash scripts/build.sh` now runs on a
  copied-out crate with neither git nor moon present, which is closer to
  adr-0001's standalone requirement than what it replaces.
- **The gate still fires only when the task runs.** Unchanged from adr-0001: a
  `src/` edit committed without running the build is caught by the next
  `moon ci` that selects the task, not at the moment of the commit.
- **`.prototools` pins `rust = "stable"`, so the artifact is still hostage to
  the next stable release.** Within one host architecture, a new stable will
  change the bytes. That no longer fails the gate, which is the point — but it
  also means "which rustc built the committed artifact" is not recorded
  anywhere. Whether to pin an exact rust version is left open, and is in
  PLAN.md's risk table rather than decided here: pinning would change every
  Rust task's hash across the workspace and force a rustup download, which is
  not this change's business.

## Alternatives considered

**Keep byte-equality and fix the environment.** Rejected as unavailable, not
as undesirable. It needs every machine that runs the task to share a host
architecture; CI runs on x86_64 hosted runners and this workspace's sandbox is
aarch64.

**Declare x86_64 canonical: byte-compare only when `rustc -vV`'s host matches,
skip elsewhere.** This keeps CI as the strict gate, which is the gate that
matters. Rejected on two findings. The committed artifact would have to be
produced on x86_64, and it cannot be produced here: with the `qemu-x86_64`
binfmt handler registered, `docker run --platform linux/amd64 rust:1.98-slim
rustc --version` dies with `qemu: uncaught target signal 11 (Segmentation
fault)`, so the one artifact needed to bootstrap the scheme would have to be
lifted by hand out of a CI run. And it makes the gate inert on every developer
machine in this repository, which is where a stale artifact is actually
created.

**Build the WASM inside a fixed-platform container.** Reproducible by
construction, and dead for the same qemu reason: an aarch64 developer could
not run it.

**Record moon's own task hash instead of a source digest.** Attractive because
adr-0006 endorses asking moon rather than reconstructing its hashing rule.
Rejected because a task hash folds in the toolchain version and the command,
so it moves whenever rust moves — which is exactly the variance this ADR
exists to tolerate. moon 2 also exposes no `query hash` to read it back.

**Read the input list from moon at build time.** Implemented first, and
reverted on the flakiness measured above. What survives of it is the pair of
comments naming the coupling, which is weaker: unlike the sandbox image tag,
where drift can only cost a cache miss, an input listed in moon.yml and left
out of `SOURCE_PATHS` lets a stale artifact pass. Accepted as the residual
risk, on the grounds that it takes a deliberate edit to one of two adjacent
lists, and that the alternative was a gate failing one run in six.

**Stop committing the artifact.** Rejected by adr-0001 on bootstrap grounds
that have not changed: `moon` alone must be sufficient to work in this repo.

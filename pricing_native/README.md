# pricing_native

**Language:** Elixir

**Purpose:** Rustler NIF facade; sole referencer of the NIF module.

## The facade

- **`PricingNative.quote/3`** (`lib/pricing_native.ex`) is the only
  sanctioned entry point: takes plain maps for travel/labour params and a
  list of parts maps, calls through to the compiled NIF, and returns a map
  breakdown (`travel_cents`, `labour_cents`, `parts_cents`, `total_cents`).
- **`PricingNative.Native`** (`lib/pricing_native/native.ex`) is the raw
  Rustler NIF module — `use Boundary, exports: []`, a sub-boundary of
  `PricingNative` that exports nothing beyond itself, so only `PricingNative`
  (its parent boundary) may call it. Verified with a throwaway probe module
  (`lib/probe.ex`, a top-level module *outside* the `PricingNative`
  namespace declaring no dependency on it) that called
  `PricingNative.Native.quote/6` directly: `mix compile --warnings-as-errors`
  failed with `forbidden reference to PricingNative.Native`, as expected.
  The probe was deleted afterward; compilation is clean again.
- **`native/pricingnative/`** is the actual Rustler NIF crate: a Cargo
  *path* dependency on `../../../pricing`, so the NIF compiles from that
  crate's real source rather than a precompiled binary, wrapping
  `pricing::quote` behind primitive-typed `#[rustler::nif]` functions.
- **Declared cross-language edge**: `moon.yml` has a project-level
  `dependsOn: [pricing]` (ownership/graph-structure) and a task `deps` on
  `pricing:build`. That task declares the compiled rlib as its `outputs`,
  which is what makes it contribute to this project's task hashes — see
  `../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md`.

## Local setup

```bash
cd pricing_native
mix deps.get
mix test
```

Or, via Moon: `moon run pricing_native:test` from the repo root.

No database, no `Application` supervision tree — this app's only job is
hosting the NIF, so there's nothing to boot.

Note: the Moon task, and the commands above, redirect `CARGO_TARGET_DIR`
under `$HOME`, so the Rustler-invoked `cargo rustc` never writes an in-tree
`target/` into this project's `native/**/*` input glob.

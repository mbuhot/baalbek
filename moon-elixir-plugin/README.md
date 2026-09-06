# moon-elixir-plugin

**Language:** Rust → WASM

**Purpose:** Mix path-dep inference.

A Moon WASM toolchain plugin that parses `mix.exs` path dependencies and
infers `dependsOn` between Elixir projects, replacing the hand-maintained
drift-check script introduced in Stage 1. Skeleton only (Stage 0) — no
`Cargo.toml` or `moon.yml` yet; those land in Stage 1 and Stage 11.

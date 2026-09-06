# pricing_native

**Language:** Elixir

**Purpose:** Rustler NIF facade; sole referencer of the NIF module.

`boundary` enforces that no other app references the NIF module directly.
Not a precompiled-binary NIF — the `pricing` crate compiles as a real,
declared source dependency (see PLAN.md §3 "Rust: NIF behind a facade app").
Skeleton only (Stage 0) — no `mix.exs` or `moon.yml` yet; those land in
Stage 1 and Stage 4.

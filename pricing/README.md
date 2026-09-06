# pricing

**Language:** Rust crate

**Purpose:** Quote computation: travel + labour + parts. `cargo test`.

Compiles outside Mix's dependency graph; the crate → `pricing_native` facade
edge is declared explicitly in Moon (`dependsOn`), per PLAN.md's "Two
facades, one pattern". Skeleton only (Stage 0) — no `Cargo.toml` or
`moon.yml` yet; those land in Stage 1 and Stage 4.

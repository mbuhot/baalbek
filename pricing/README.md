# pricing

**Language:** Rust crate

**Purpose:** Quote computation: travel + labour + parts.

## Stage 4 (this stage)

- Plain-struct public API (`TravelParams`, `LabourParams`, `PartLineItem`,
  `Quote`) built from primitives (`f64`, `i64`, `u32`) that Rustler can pass
  across the NIF boundary natively — no custom `Encoder`/`Decoder` needed.
  All monetary amounts are integer cents; rounding from a float input
  happens exactly once, at the point it becomes money.
- `travel_cost_cents/1`: distance × per-km rate.
- `labour_cost_cents/1`: hours × hourly rate, floored at a minimum callout
  charge.
- `parts_cost_cents/1`: sum of quantity × unit price over a list of line
  items.
- `quote/3`: combines all three into a `Quote{travel_cents, labour_cents,
  parts_cents, total_cents}`.
- `apply_percent_discount_cents/2`, `round_up_to_dollar_cents/1`,
  `is_discount_applicable/1`: small extra helpers added to exercise Stage
  4's Moon cache-invalidation proof with a genuine behavioural change
  (see the Stage 4 report for the before/after hashes).

Compiles outside Mix's dependency graph; the crate → `pricing_native` facade
edge is declared explicitly on the `pricing_native` side, both as a project
`dependsOn` and as a `project://pricing` task input (per PLAN.md's "Two
facades, one pattern" — see `pricing_native/moon.yml`'s comments for why
both are needed).

## Local setup

```bash
cd pricing
cargo test
```

Or, via Moon: `moon run pricing:test` from the repo root.

Note: this sandbox mounts the repo over virtiofs, which was observed
(Stage 4 development) to occasionally fail Cargo's concurrent target-dir
directory creation with a spurious `EEXIST`. The Moon task redirects
`CARGO_TARGET_DIR` under `$HOME` to avoid it; running `cargo test` directly
falls back to an in-tree `target/` (gitignored), which works too, just
without that workaround.

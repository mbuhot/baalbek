# pricing

**Language:** Rust crate

**Purpose:** Quote computation: travel + labour + parts.

## The API

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
  `is_discount_applicable/1`: small extra helpers.

Compiles outside Mix's dependency graph; the crate → `pricing_native` facade
edge is declared on the `pricing_native` side as a project `dependsOn` plus a
task `deps` on `pricing:build`, whose declared output is the compiled rlib
(`../spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md`).

## Local setup

```bash
cd pricing
cargo test
```

Or, via Moon: `moon run pricing:test` from the repo root.

Note: the Moon task redirects `CARGO_TARGET_DIR` under `$HOME`, so an
in-tree `target/` stays out of `pricing_native`'s `native/**/*` input glob.
Running `cargo test` directly falls back to an in-tree `target/`
(gitignored), which works too.

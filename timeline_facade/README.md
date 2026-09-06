# timeline_facade

**Language:** Elixir

**Purpose:** Sole caller of the Gleam `timeline` modules; `boundary`-enforced.

Declares an explicit Moon `dependsOn` edge to the `timeline` (Gleam) project
so a Gleam change invalidates this facade's tests. Skeleton only (Stage 0) —
no `mix.exs` or `moon.yml` yet; those land in Stage 1 and Stage 5.

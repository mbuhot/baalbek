defmodule PricingNative do
  @moduledoc """
  Public API boundary (seed.md §3, "Within-app boundaries: boundary") and
  Rustler NIF facade (seed.md §3, "Rust: NIF behind a facade app") for the
  `pricing` Rust crate.

  `pricing_native`'s entire purpose is hosting the Rustler NIF that wraps
  `pricing`'s quote computation and exposing exactly one clean entry point:
  `quote/3`. The raw NIF module, `PricingNative.Native`, is a sub-boundary
  that exports nothing, so no other app — and no other module in this app —
  may reference it directly; only this module may. `mix compile
  --warnings-as-errors` fails if that's violated (see this app's Stage 4
  boundary-violation probe, and `core`'s Stage 2 report for the same
  technique).

  `pricing` compiles outside Mix's dependency graph (it's a Cargo project,
  not a Mix path dependency), so the `pricing_native -> pricing` edge is
  declared explicitly as `dependsOn` in this app's `moon.yml`, per PLAN.md's
  "Two facades, one pattern" — that's what makes a `pricing` crate change
  invalidate this app's cached Moon test results, and it's also why
  `check-deps-drift.py` correctly leaves this edge alone (it's a
  cross-language edge, not a Mix path dep).
  """

  use Boundary, deps: [], exports: []

  @type travel_params :: %{distance_km: number(), rate_per_km_cents: integer()}
  @type labour_params :: %{
          hours: number(),
          hourly_rate_cents: integer(),
          minimum_charge_cents: integer()
        }
  @type part_line_item :: %{quantity: non_neg_integer(), unit_price_cents: integer()}
  @type quote :: %{
          travel_cents: integer(),
          labour_cents: integer(),
          parts_cents: integer(),
          total_cents: integer()
        }

  @doc """
  Computes a field-service job quote from its three components, via the
  `pricing` crate's `quote/3` function.

      iex> PricingNative.quote(
      ...>   %{distance_km: 10.0, rate_per_km_cents: 150},
      ...>   %{hours: 2.0, hourly_rate_cents: 8000, minimum_charge_cents: 10_000},
      ...>   [%{quantity: 2, unit_price_cents: 500}]
      ...> )
      %{travel_cents: 1500, labour_cents: 16000, parts_cents: 1000, total_cents: 18500}

  """
  @spec quote(travel_params(), labour_params(), [part_line_item()]) :: quote()
  def quote(travel, labour, parts) do
    parts_tuples = Enum.map(parts, fn part -> {part.quantity, part.unit_price_cents} end)

    {travel_cents, labour_cents, parts_cents, total_cents} =
      PricingNative.Native.quote(
        travel.distance_km * 1.0,
        travel.rate_per_km_cents,
        labour.hours * 1.0,
        labour.hourly_rate_cents,
        labour.minimum_charge_cents,
        parts_tuples
      )

    %{
      travel_cents: travel_cents,
      labour_cents: labour_cents,
      parts_cents: parts_cents,
      total_cents: total_cents
    }
  end
end

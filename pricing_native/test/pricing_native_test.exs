defmodule PricingNativeTest do
  @moduledoc """
  Exercises `PricingNative.quote/3` end to end through the real compiled
  NIF (no stubbing — per seed.md §7's governing principle, this suite must
  be a real proof that the `pricing` crate is actually being called).
  """

  use ExUnit.Case, async: true

  doctest PricingNative

  describe "quote/3" do
    test "sums travel, labour, and parts" do
      result =
        PricingNative.quote(
          %{distance_km: 42.0, rate_per_km_cents: 150},
          %{hours: 3.0, hourly_rate_cents: 8000, minimum_charge_cents: 10_000},
          [
            %{quantity: 2, unit_price_cents: 500},
            %{quantity: 1, unit_price_cents: 12_000}
          ]
        )

      assert result == %{
               travel_cents: 6300,
               labour_cents: 24_000,
               parts_cents: 13_000,
               total_cents: 43_300
             }
    end

    test "zero parts costs nothing" do
      result =
        PricingNative.quote(
          %{distance_km: 10.0, rate_per_km_cents: 100},
          %{hours: 1.0, hourly_rate_cents: 5000, minimum_charge_cents: 5000},
          []
        )

      assert result.parts_cents == 0
      assert result.total_cents == result.travel_cents + result.labour_cents
    end

    test "labour floors at the minimum callout charge" do
      result =
        PricingNative.quote(
          %{distance_km: 0.0, rate_per_km_cents: 150},
          %{hours: 0.1, hourly_rate_cents: 8000, minimum_charge_cents: 10_000},
          []
        )

      assert result.labour_cents == 10_000
      assert result.total_cents == 10_000
    end

    test "zero distance costs nothing in travel" do
      result =
        PricingNative.quote(
          %{distance_km: 0.0, rate_per_km_cents: 999},
          %{hours: 0.0, hourly_rate_cents: 0, minimum_charge_cents: 0},
          []
        )

      assert result == %{travel_cents: 0, labour_cents: 0, parts_cents: 0, total_cents: 0}
    end
  end
end

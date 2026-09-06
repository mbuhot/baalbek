defmodule PricingNative do
  @moduledoc """
  Elixir facade for the `pricing` Rust crate's job-quote computation.

  This module is the only sanctioned caller of `PricingNative.Native`, the
  raw NIF module; every other caller, in this app or any other, goes
  through `quote/3` instead. That keeps the compiled-NIF boundary in one
  place, so a future change to the NIF's argument shape touches only here.
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
  Computes a field-service job quote from its travel, labour, and parts components.

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

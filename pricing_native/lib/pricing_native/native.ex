defmodule PricingNative.Native do
  @moduledoc """
  Raw Rustler NIF module wrapping the `pricing` crate; callers must go through `PricingNative.quote/3` instead.
  """

  use Boundary, exports: []

  use Rustler, otp_app: :pricing_native, crate: "pricingnative"

  @doc "Stub replaced by the compiled NIF at load time; raises if the NIF failed to load."
  @spec quote(float(), integer(), float(), integer(), integer(), [{non_neg_integer(), integer()}]) ::
          {integer(), integer(), integer(), integer()}
  def quote(
        _distance_km,
        _rate_per_km_cents,
        _labour_hours,
        _hourly_rate_cents,
        _minimum_charge_cents,
        _parts
      ),
      do: :erlang.nif_error(:nif_not_loaded)
end

defmodule PricingNative.Native do
  @moduledoc """
  Raw Rustler NIF module wrapping the `pricing` crate (seed.md §3, "Rust:
  NIF behind a facade app").

  This is a sub-boundary of `PricingNative` that exports nothing
  (`exports: []`), which is what makes it invisible to every boundary other
  than its parent, `PricingNative` — the one sanctioned caller (`boundary`
  automatically lets a parent boundary's modules use whatever a direct
  child sub-boundary exports; see `PricingNative`'s moduledoc and
  `core/lib/core.ex`'s for the same pattern applied to `Core.Data`). No
  other app, and no other module in this app, may call `quote/6` directly —
  only `PricingNative.quote/3` may.

  Do not add convenience functions or re-exports here beyond the raw NIF
  stubs: this module's only job is hosting compiled Rust, nothing else.
  """

  use Boundary, exports: []

  use Rustler, otp_app: :pricing_native, crate: "pricingnative"

  # Stubs replaced by the compiled NIF at load time. If the NIF failed to
  # load (e.g. the crate didn't compile), calling this raises instead of
  # silently returning a placeholder value.
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

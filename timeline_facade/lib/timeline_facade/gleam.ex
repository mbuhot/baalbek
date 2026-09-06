defmodule TimelineFacade.Gleam do
  @moduledoc """
  Raw bridge to the compiled `timeline` Gleam module. A sub-boundary that
  exports nothing, so only its parent, `TimelineFacade`, may call it.
  Pass-through only: no decoding, no convenience functions.
  """

  use Boundary, exports: []

  @doc "Calls `timeline`'s `append_shift_started/2` directly."
  @spec append_shift_started(String.t(), integer()) :: {:ok, nil} | {:error, String.t()}
  def append_shift_started(technician_id, occurred_at),
    do: :timeline.append_shift_started(technician_id, occurred_at)

  @doc "Calls `timeline`'s `append_shift_ended/2` directly."
  @spec append_shift_ended(String.t(), integer()) :: {:ok, nil} | {:error, String.t()}
  def append_shift_ended(technician_id, occurred_at),
    do: :timeline.append_shift_ended(technician_id, occurred_at)

  @doc "Calls `timeline`'s `append_travel_started/3` directly."
  @spec append_travel_started(String.t(), integer(), String.t()) ::
          {:ok, nil} | {:error, String.t()}
  def append_travel_started(technician_id, occurred_at, destination_site_id),
    do: :timeline.append_travel_started(technician_id, occurred_at, destination_site_id)

  @doc "Calls `timeline`'s `append_arrived_on_site/3` directly."
  @spec append_arrived_on_site(String.t(), integer(), String.t()) ::
          {:ok, nil} | {:error, String.t()}
  def append_arrived_on_site(technician_id, occurred_at, site_id),
    do: :timeline.append_arrived_on_site(technician_id, occurred_at, site_id)

  @doc "Calls `timeline`'s `append_departed_site/3` directly."
  @spec append_departed_site(String.t(), integer(), String.t()) ::
          {:ok, nil} | {:error, String.t()}
  def append_departed_site(technician_id, occurred_at, site_id),
    do: :timeline.append_departed_site(technician_id, occurred_at, site_id)

  @doc "Calls `timeline`'s `rebuild_availability/1` directly."
  @spec rebuild_availability(String.t()) ::
          {:ok, {String.t(), String.t()}} | {:error, String.t()}
  def rebuild_availability(technician_id),
    do: :timeline.rebuild_availability(technician_id)

  @doc "Calls `timeline`'s `current_availability/1` directly."
  @spec current_availability(String.t()) ::
          {:ok, {String.t(), String.t()}} | {:error, String.t()}
  def current_availability(technician_id),
    do: :timeline.current_availability(technician_id)
end

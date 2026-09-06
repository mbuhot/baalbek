defmodule Server.Timeline do
  @moduledoc """
  Technician availability, read and written through `timeline_facade`.

  The only path from `server` into the Gleam `timeline` package, and the one
  the HTTP surface uses to prove the release bundles it.
  """

  @site_event_kinds ~w(travel_started arrived_on_site departed_site)

  @typedoc "`%{status: atom, site_id: String.t() | nil}` for one technician."
  @type availability :: %{status: atom(), site_id: String.t() | nil}

  @doc "Replays a technician's event log, persists the projection, and returns the result."
  @spec availability(String.t()) :: {:ok, availability()} | {:error, String.t()}
  def availability(technician_id) do
    with {:ok, {status, site_id}} <- TimelineFacade.rebuild_availability(technician_id) do
      {:ok, %{status: status, site_id: site_id}}
    end
  end

  @doc """
  Appends one event to a technician's log.

  `kind` is one of `shift_started`, `shift_ended`, `travel_started`,
  `arrived_on_site`, `departed_site`. The last three need a `site_id`.
  """
  @spec append_event(String.t(), String.t(), integer(), String.t() | nil) ::
          :ok | {:error, String.t()}
  def append_event(technician_id, kind, occurred_at, site_id \\ nil)

  def append_event(technician_id, "shift_started", occurred_at, _site_id),
    do: TimelineFacade.append_shift_started(technician_id, occurred_at)

  def append_event(technician_id, "shift_ended", occurred_at, _site_id),
    do: TimelineFacade.append_shift_ended(technician_id, occurred_at)

  def append_event(_technician_id, kind, _occurred_at, nil) when kind in @site_event_kinds,
    do: {:error, "#{kind} requires site_id"}

  def append_event(technician_id, "travel_started", occurred_at, site_id),
    do: TimelineFacade.append_travel_started(technician_id, occurred_at, site_id)

  def append_event(technician_id, "arrived_on_site", occurred_at, site_id),
    do: TimelineFacade.append_arrived_on_site(technician_id, occurred_at, site_id)

  def append_event(technician_id, "departed_site", occurred_at, site_id),
    do: TimelineFacade.append_departed_site(technician_id, occurred_at, site_id)

  def append_event(_technician_id, kind, _occurred_at, _site_id),
    do: {:error, "unknown event kind #{inspect(kind)}"}
end

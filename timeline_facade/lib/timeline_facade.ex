defmodule TimelineFacade do
  @moduledoc """
  Public API and sole caller of the `timeline` Gleam package.

  Loads timeline's compiled output onto this project's code path (see
  mix.exs) and exposes an idiomatic Elixir surface over it: atoms for
  status, `nil` for "no site", plain `:ok`/`:error` tuples. The raw Gleam
  calls live in `TimelineFacade.Gleam`, a sub-boundary nothing else may
  reach. See docs/adr-0001-gleam-elixir-interop.md for the full interop
  story.
  """

  use Boundary, deps: [], exports: []

  @typedoc "One of the technician-timeline event kinds `timeline` understands."
  @type status :: :off_shift | :on_shift | :travelling | :on_site

  @typedoc "`{status, site_id}` — `site_id` is `nil` when not travelling/on-site."
  @type availability :: {status(), String.t() | nil}

  @doc "Technician clocks on for a shift."
  @spec append_shift_started(String.t(), integer()) :: :ok | {:error, String.t()}
  def append_shift_started(technician_id, occurred_at) do
    ok_or_error(TimelineFacade.Gleam.append_shift_started(technician_id, occurred_at))
  end

  @doc "Technician clocks off."
  @spec append_shift_ended(String.t(), integer()) :: :ok | {:error, String.t()}
  def append_shift_ended(technician_id, occurred_at) do
    ok_or_error(TimelineFacade.Gleam.append_shift_ended(technician_id, occurred_at))
  end

  @doc "Technician starts travelling towards `destination_site_id`."
  @spec append_travel_started(String.t(), integer(), String.t()) :: :ok | {:error, String.t()}
  def append_travel_started(technician_id, occurred_at, destination_site_id) do
    ok_or_error(
      TimelineFacade.Gleam.append_travel_started(technician_id, occurred_at, destination_site_id)
    )
  end

  @doc "Technician arrives at `site_id`."
  @spec append_arrived_on_site(String.t(), integer(), String.t()) :: :ok | {:error, String.t()}
  def append_arrived_on_site(technician_id, occurred_at, site_id) do
    ok_or_error(TimelineFacade.Gleam.append_arrived_on_site(technician_id, occurred_at, site_id))
  end

  @doc "Technician departs `site_id`."
  @spec append_departed_site(String.t(), integer(), String.t()) :: :ok | {:error, String.t()}
  def append_departed_site(technician_id, occurred_at, site_id) do
    ok_or_error(TimelineFacade.Gleam.append_departed_site(technician_id, occurred_at, site_id))
  end

  @doc """
  Replays `technician_id`'s full event log and persists the resulting
  availability into the `timeline.availability` projection table.
  """
  @spec rebuild_availability(String.t()) :: {:ok, availability()} | {:error, String.t()}
  def rebuild_availability(technician_id) do
    with {:ok, tuple} <- TimelineFacade.Gleam.rebuild_availability(technician_id) do
      {:ok, to_availability(tuple)}
    end
  end

  @doc """
  Reads the already-materialised availability projection directly (no
  replay of the event log). `{:error, _}` means no projection row exists
  yet for this technician — `rebuild_availability/1` has never run for them.
  """
  @spec current_availability(String.t()) :: {:ok, availability()} | {:error, String.t()}
  def current_availability(technician_id) do
    with {:ok, tuple} <- TimelineFacade.Gleam.current_availability(technician_id) do
      {:ok, to_availability(tuple)}
    end
  end

  defp ok_or_error({:ok, nil}), do: :ok
  defp ok_or_error({:error, _reason} = error), do: error

  # `String.to_atom/1` (not `to_existing_atom/1`) is safe here: `status_string`
  # is never caller/user-controlled input — it only ever comes back from
  # `timeline`'s own fixed, four-member vocabulary (see
  # timeline/src/timeline/availability.gleam's `status_to_string/1`), so
  # there's no atom-table exhaustion risk.
  defp to_availability({status_string, site_id_string}) do
    {String.to_atom(status_string), nilify(site_id_string)}
  end

  defp nilify(""), do: nil
  defp nilify(site_id), do: site_id
end

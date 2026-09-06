defmodule TimelineFacadeTest do
  @moduledoc """
  Exercises `TimelineFacade`'s public functions against the real `timeline`
  Postgres schema/role, with no stubbing.

  Each test uses a fresh technician_id combining wall-clock time with
  `System.unique_integer/1`: the counter alone resets every VM restart and
  can collide with a past run's leftover events (the log is append-only,
  nothing deletes them), corrupting that id's projection.
  """

  use ExUnit.Case, async: true

  defp unique_technician_id(label) do
    "facade-test-#{label}-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive, :monotonic])}"
  end

  describe "append_* and rebuild_availability/1" do
    test "shift -> travel -> arrive -> depart -> shift end returns to off_shift" do
      technician_id = unique_technician_id("full-shift")

      assert :ok = TimelineFacade.append_shift_started(technician_id, 1_000)
      assert :ok = TimelineFacade.append_travel_started(technician_id, 1_100, "site-1")
      assert :ok = TimelineFacade.append_arrived_on_site(technician_id, 1_200, "site-1")

      assert {:ok, {:on_site, "site-1"}} = TimelineFacade.rebuild_availability(technician_id)

      assert :ok = TimelineFacade.append_departed_site(technician_id, 1_300, "site-1")
      assert {:ok, {:on_shift, nil}} = TimelineFacade.rebuild_availability(technician_id)

      assert :ok = TimelineFacade.append_shift_ended(technician_id, 1_400)
      assert {:ok, {:off_shift, nil}} = TimelineFacade.rebuild_availability(technician_id)
    end

    test "travel without a prior shift start still projects to travelling" do
      technician_id = unique_technician_id("travel-only")

      assert :ok = TimelineFacade.append_travel_started(technician_id, 500, "site-9")

      assert {:ok, {:travelling, "site-9"}} = TimelineFacade.rebuild_availability(technician_id)
    end
  end

  describe "current_availability/1" do
    test "reads the live projection written by rebuild_availability/1" do
      technician_id = unique_technician_id("live-projection")

      assert :ok = TimelineFacade.append_shift_started(technician_id, 2_000)
      assert :ok = TimelineFacade.append_travel_started(technician_id, 2_100, "site-42")

      assert {:ok, {:travelling, "site-42"}} =
               TimelineFacade.rebuild_availability(technician_id)

      assert {:ok, {:travelling, "site-42"}} =
               TimelineFacade.current_availability(technician_id)
    end

    test "errors when no projection has ever been rebuilt for this technician" do
      technician_id = unique_technician_id("no-projection-yet")

      assert {:error, message} = TimelineFacade.current_availability(technician_id)
      assert message =~ "no availability projection yet"
    end
  end
end

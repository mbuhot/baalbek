defmodule ServerWeb.TimelineRouterTest do
  @moduledoc """
  Exercises `/api/timeline` end to end, through the real `timeline` Gleam
  package and its Postgres schema/role, with no stubbing.

  The same request path the release gate uses, so a regression that stops
  `server` reaching the Gleam code fails here too.
  """

  use ServerWeb.ConnCase, async: true

  # The event log is append-only and nothing deletes it, so ids must not
  # collide with a past run's (same reason as timeline_facade's own suite).
  defp unique_technician_id(label) do
    "server-test-#{label}-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp post_event(conn, technician_id, attrs) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/timeline/technicians/#{technician_id}/events", Jason.encode!(attrs))
  end

  describe "POST /technicians/:technician_id/events" do
    test "appends an event", %{conn: conn} do
      technician_id = unique_technician_id("append")

      conn = post_event(conn, technician_id, %{kind: "shift_started", occurred_at: 1_000})

      assert %{"data" => data} = json_response(conn, 201)
      assert data["type"] == "timeline_event"
      assert data["attributes"]["kind"] == "shift_started"
    end

    test "rejects a site event with no site_id", %{conn: conn} do
      technician_id = unique_technician_id("no-site")

      conn = post_event(conn, technician_id, %{kind: "arrived_on_site", occurred_at: 1_000})

      assert %{"errors" => [%{"detail" => detail}]} = json_response(conn, 422)
      assert detail =~ "requires site_id"
    end

    test "rejects an unknown event kind", %{conn: conn} do
      technician_id = unique_technician_id("unknown-kind")

      conn = post_event(conn, technician_id, %{kind: "teleported", occurred_at: 1_000})

      assert %{"errors" => [%{"detail" => detail}]} = json_response(conn, 422)
      assert detail =~ "unknown event kind"
    end

    test "rejects a missing occurred_at", %{conn: conn} do
      technician_id = unique_technician_id("no-time")

      conn = post_event(conn, technician_id, %{kind: "shift_started"})

      assert %{"errors" => [%{"detail" => "occurred_at is required"}]} = json_response(conn, 422)
    end
  end

  describe "GET /technicians/:technician_id/availability" do
    test "projects the appended events", %{conn: conn} do
      technician_id = unique_technician_id("availability")

      assert %{"data" => _} =
               conn
               |> post_event(technician_id, %{kind: "shift_started", occurred_at: 1_000})
               |> json_response(201)

      assert %{"data" => _} =
               build_conn()
               |> post_event(technician_id, %{
                 kind: "arrived_on_site",
                 occurred_at: 1_100,
                 site_id: "site-7"
               })
               |> json_response(201)

      conn = get(build_conn(), "/api/timeline/technicians/#{technician_id}/availability")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["type"] == "availability"
      assert data["id"] == technician_id
      assert data["attributes"] == %{"status" => "on_site", "site_id" => "site-7"}
    end

    test "an unknown technician projects to off_shift", %{conn: conn} do
      technician_id = unique_technician_id("unknown")

      conn = get(conn, "/api/timeline/technicians/#{technician_id}/availability")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["attributes"] == %{"status" => "off_shift", "site_id" => nil}
    end
  end
end

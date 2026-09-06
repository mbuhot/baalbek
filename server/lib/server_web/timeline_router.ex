defmodule ServerWeb.TimelineRouter do
  @moduledoc """
  Technician timeline routes, mounted under `/api/timeline`.

  Plain JSON, not JSON:API: `timeline` is an event-sourced Gleam package,
  not an Ash resource, so `ash_json_api` has nothing to generate from.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  get "/technicians/:technician_id/availability" do
    case Server.Timeline.availability(technician_id) do
      {:ok, availability} ->
        send_json(conn, 200, %{
          data: %{
            type: "availability",
            id: technician_id,
            attributes: %{status: availability.status, site_id: availability.site_id}
          }
        })

      {:error, reason} ->
        send_json(conn, 502, %{errors: [%{detail: reason}]})
    end
  end

  post "/technicians/:technician_id/events" do
    params = conn.body_params
    kind = params["kind"]
    site_id = params["site_id"]

    with {:ok, occurred_at} <- occurred_at(params["occurred_at"]),
         :ok <- Server.Timeline.append_event(technician_id, kind, occurred_at, site_id) do
      send_json(conn, 201, %{
        data: %{
          type: "timeline_event",
          attributes: %{
            technician_id: technician_id,
            kind: kind,
            occurred_at: occurred_at,
            site_id: site_id
          }
        }
      })
    else
      {:error, reason} -> send_json(conn, 422, %{errors: [%{detail: reason}]})
    end
  end

  match _ do
    send_json(conn, 404, %{errors: [%{detail: "no such timeline route"}]})
  end

  defp occurred_at(value) when is_integer(value), do: {:ok, value}

  defp occurred_at(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} -> {:ok, seconds}
      _ -> {:error, "occurred_at must be an integer"}
    end
  end

  defp occurred_at(_value), do: {:error, "occurred_at is required"}

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end

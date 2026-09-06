//// Public API of the `timeline` package — the only surface
//// `timeline_facade` (Elixir) is meant to call. Every function here takes
//// and returns only primitives (`String`, `Int`, plain `Result`, a bare
//// `#(String, String)` tuple for availability), so nothing outside this
//// module needs to decode a Gleam-specific type.

import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import pog
import timeline/availability.{type Availability}
import timeline/db
import timeline/event.{type Kind}

fn connect_error_to_string(error: actor.StartError) -> String {
  "timeline: could not connect to postgres: " <> string.inspect(error)
}

fn query_error_to_string(error: pog.QueryError) -> String {
  "timeline: query failed: " <> string.inspect(error)
}

fn site_id_or_none(site_id: String) -> Option(String) {
  case site_id {
    "" -> None
    _ -> Some(site_id)
  }
}

fn site_id_to_string(site_id: Option(String)) -> String {
  case site_id {
    Some(id) -> id
    None -> ""
  }
}

fn availability_to_tuple(avail: Availability) -> #(String, String) {
  #(availability.status_to_string(avail.status), site_id_to_string(avail.site_id))
}

fn append(
  kind: Kind,
  technician_id: String,
  occurred_at: Int,
  site_id: String,
) -> Result(Nil, String) {
  use conn <- result.try(
    db.connect() |> result.map_error(connect_error_to_string),
  )

  let evt =
    event.Event(
      technician_id: technician_id,
      kind: kind,
      occurred_at: occurred_at,
      site_id: site_id_or_none(site_id),
    )

  event.append(conn, evt) |> result.map_error(query_error_to_string)
}

/// Records that a technician clocked on for a shift.
pub fn append_shift_started(
  technician_id: String,
  occurred_at: Int,
) -> Result(Nil, String) {
  append(event.ShiftStarted, technician_id, occurred_at, "")
}

/// Records that a technician clocked off.
pub fn append_shift_ended(
  technician_id: String,
  occurred_at: Int,
) -> Result(Nil, String) {
  append(event.ShiftEnded, technician_id, occurred_at, "")
}

/// Records that a technician started travelling towards a site.
pub fn append_travel_started(
  technician_id: String,
  occurred_at: Int,
  destination_site_id: String,
) -> Result(Nil, String) {
  append(event.TravelStarted, technician_id, occurred_at, destination_site_id)
}

/// Records that a technician arrived at a site.
pub fn append_arrived_on_site(
  technician_id: String,
  occurred_at: Int,
  site_id: String,
) -> Result(Nil, String) {
  append(event.ArrivedOnSite, technician_id, occurred_at, site_id)
}

/// Records that a technician departed a site.
pub fn append_departed_site(
  technician_id: String,
  occurred_at: Int,
  site_id: String,
) -> Result(Nil, String) {
  append(event.DepartedSite, technician_id, occurred_at, site_id)
}

/// Replay `technician_id`'s full event log and persist the resulting
/// availability into the projection table. Returns `#(status, site_id)`.
pub fn rebuild_availability(technician_id: String) -> Result(#(String, String), String) {
  use conn <- result.try(
    db.connect() |> result.map_error(connect_error_to_string),
  )

  use avail <- result.try(
    availability.rebuild(conn, technician_id)
    |> result.map_error(query_error_to_string),
  )

  Ok(availability_to_tuple(avail))
}

/// Read the already-materialised availability projection directly (no
/// replay). `Error` means no projection row exists yet for this
/// technician — `rebuild_availability/1` has never run for them.
pub fn current_availability(technician_id: String) -> Result(#(String, String), String) {
  use conn <- result.try(
    db.connect() |> result.map_error(connect_error_to_string),
  )

  use maybe_avail <- result.try(
    availability.current(conn, technician_id)
    |> result.map_error(query_error_to_string),
  )

  case maybe_avail {
    Some(avail) -> Ok(availability_to_tuple(avail))
    None ->
      Error(
        "timeline: no availability projection yet for technician "
        <> technician_id,
      )
  }
}

//// The "current availability" projection. Derived entirely from
//// `timeline/event.gleam`'s append-only log; never written to directly.
//// `project/1` is the pure fold; `rebuild/2` and `current/2` are its I/O
//// wrappers.

import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import pog
import timeline/event.{type Event}

/// A technician's current state: off shift, on shift, travelling, or on
/// site.
pub type Status {
  OffShift
  OnShift
  Travelling
  OnSite
}

/// A technician's status plus the site they're at or heading to, if any.
pub type Availability {
  Availability(status: Status, site_id: Option(String))
}

/// The column value stored for a status in `timeline.availability`.
pub fn status_to_string(status: Status) -> String {
  case status {
    OffShift -> "off_shift"
    OnShift -> "on_shift"
    Travelling -> "travelling"
    OnSite -> "on_site"
  }
}

/// Parses a status back from its stored column value.
pub fn status_from_string(value: String) -> Result(Status, Nil) {
  case value {
    "off_shift" -> Ok(OffShift)
    "on_shift" -> Ok(OnShift)
    "travelling" -> Ok(Travelling)
    "on_site" -> Ok(OnSite)
    _ -> Error(Nil)
  }
}

/// Before any event has ever been appended for a technician.
pub fn initial() -> Availability {
  Availability(status: OffShift, site_id: None)
}

/// One event's effect on availability. Pure: no I/O.
///
/// `DepartedSite` moves a technician to `OnShift`, not back to
/// `Travelling`: this vocabulary has no separate "returned to base" event.
/// `_current` is unused. Every event kind fully determines the next state
/// on its own; the parameter stays so `list.fold` can use this directly.
pub fn apply_event(_current: Availability, evt: Event) -> Availability {
  case evt.kind {
    event.ShiftStarted -> Availability(status: OnShift, site_id: None)
    event.ShiftEnded -> Availability(status: OffShift, site_id: None)
    event.TravelStarted ->
      Availability(status: Travelling, site_id: evt.site_id)
    event.ArrivedOnSite -> Availability(status: OnSite, site_id: evt.site_id)
    event.DepartedSite -> Availability(status: OnShift, site_id: None)
  }
}

/// Rebuild a technician's availability from scratch by folding over their
/// full ordered event log. This is the event-sourcing property PLAN.md
/// names directly: "projection tables rebuilt from the log."
pub fn project(events: List(Event)) -> Availability {
  list.fold(events, initial(), apply_event)
}

fn site_id_value(site_id: Option(String)) -> pog.Value {
  case site_id {
    Some(id) -> pog.text(id)
    None -> pog.null()
  }
}

fn row_decoder() -> decode.Decoder(Availability) {
  use status_string <- decode.field(0, decode.string)
  use site_id <- decode.field(1, decode.optional(decode.string))

  case status_from_string(status_string) {
    Ok(status) -> decode.success(Availability(status: status, site_id: site_id))
    Error(Nil) -> decode.failure(initial(), "timeline.availability.status")
  }
}

/// Replay `technician_id`'s full event log and upsert the resulting state
/// into the `timeline.availability` projection table.
pub fn rebuild(
  db: pog.Connection,
  technician_id: String,
) -> Result(Availability, pog.QueryError) {
  use events <- result.try(event.list_for_technician(db, technician_id))
  let availability = project(events)

  let sql =
    "insert into timeline.availability (technician_id, status, site_id, updated_at)
     values ($1, $2, $3, now())
     on conflict (technician_id)
     do update set
       status = excluded.status,
       site_id = excluded.site_id,
       updated_at = excluded.updated_at"

  use _ <- result.try(
    pog.query(sql)
    |> pog.parameter(pog.text(technician_id))
    |> pog.parameter(pog.text(status_to_string(availability.status)))
    |> pog.parameter(site_id_value(availability.site_id))
    |> pog.returning(decode.success(Nil))
    |> pog.execute(db),
  )

  Ok(availability)
}

/// Read the already-materialised projection directly — "availability
/// queries read projections" (PLAN.md), no replay of the log involved.
/// `Ok(None)` means no projection row exists yet for this technician (no
/// events have ever been rebuilt for them).
pub fn current(
  db: pog.Connection,
  technician_id: String,
) -> Result(Option(Availability), pog.QueryError) {
  let sql =
    "select status, site_id from timeline.availability where technician_id = $1"

  use returned <- result.try(
    pog.query(sql)
    |> pog.parameter(pog.text(technician_id))
    |> pog.returning(row_decoder())
    |> pog.execute(db),
  )

  case returned.rows {
    [availability] -> Ok(Some(availability))
    _ -> Ok(None)
  }
}

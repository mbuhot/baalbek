//// Append-only event log for a technician timeline (PLAN.md "Data layer":
//// "Event sourcing in `timeline`: append-only event table plus projection
//// tables rebuilt from the log."). Nothing here ever updates or deletes a
//// row — `timeline/availability.gleam` is the only thing that rebuilds
//// derived state from what's appended here.

import gleam/dynamic/decode
import gleam/option.{type Option, None}
import gleam/result
import pog

/// The technician-timeline event vocabulary: a shift bookends travel and
/// on-site work, and travel bookends arrival/departure at a site.
pub type Kind {
  ShiftStarted
  ShiftEnded
  TravelStarted
  ArrivedOnSite
  DepartedSite
}

/// One occurrence in a technician's timeline: what happened, when, and at
/// which site (if any).
pub type Event {
  Event(
    technician_id: String,
    kind: Kind,
    occurred_at: Int,
    site_id: Option(String),
  )
}

/// The column value stored for a kind in `timeline.events`.
pub fn kind_to_string(kind: Kind) -> String {
  case kind {
    ShiftStarted -> "shift_started"
    ShiftEnded -> "shift_ended"
    TravelStarted -> "travel_started"
    ArrivedOnSite -> "arrived_on_site"
    DepartedSite -> "departed_site"
  }
}

/// Parses a kind back from its stored column value.
pub fn kind_from_string(value: String) -> Result(Kind, Nil) {
  case value {
    "shift_started" -> Ok(ShiftStarted)
    "shift_ended" -> Ok(ShiftEnded)
    "travel_started" -> Ok(TravelStarted)
    "arrived_on_site" -> Ok(ArrivedOnSite)
    "departed_site" -> Ok(DepartedSite)
    _ -> Error(Nil)
  }
}

fn row_decoder() -> decode.Decoder(Event) {
  use technician_id <- decode.field(0, decode.string)
  use kind_string <- decode.field(1, decode.string)
  use occurred_at <- decode.field(2, decode.int)
  use site_id <- decode.field(3, decode.optional(decode.string))

  case kind_from_string(kind_string) {
    Ok(kind) ->
      decode.success(Event(
        technician_id: technician_id,
        kind: kind,
        occurred_at: occurred_at,
        site_id: site_id,
      ))
    Error(Nil) ->
      decode.failure(
        Event(
          technician_id: technician_id,
          kind: ShiftStarted,
          occurred_at: 0,
          site_id: None,
        ),
        "timeline.events.kind",
      )
  }
}

fn site_id_value(site_id: Option(String)) -> pog.Value {
  case site_id {
    option.Some(id) -> pog.text(id)
    None -> pog.null()
  }
}

/// Insert one event. Append-only: there is deliberately no update/delete
/// function in this module.
pub fn append(db: pog.Connection, event: Event) -> Result(Nil, pog.QueryError) {
  let sql =
    "insert into timeline.events (technician_id, kind, occurred_at, site_id)
     values ($1, $2, $3, $4)"

  pog.query(sql)
  |> pog.parameter(pog.text(event.technician_id))
  |> pog.parameter(pog.text(kind_to_string(event.kind)))
  |> pog.parameter(pog.int(event.occurred_at))
  |> pog.parameter(site_id_value(event.site_id))
  |> pog.returning(decode.success(Nil))
  |> pog.execute(db)
  |> result.map(fn(_returned) { Nil })
}

/// The full ordered log for one technician — the thing `availability.project`
/// folds over to rebuild the projection.
pub fn list_for_technician(
  db: pog.Connection,
  technician_id: String,
) -> Result(List(Event), pog.QueryError) {
  let sql =
    "select technician_id, kind, occurred_at, site_id
     from timeline.events
     where technician_id = $1
     order by occurred_at asc, id asc"

  pog.query(sql)
  |> pog.parameter(pog.text(technician_id))
  |> pog.returning(row_decoder())
  |> pog.execute(db)
  |> result.map(fn(returned) { returned.rows })
}

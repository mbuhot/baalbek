import gleam/dynamic/decode
import gleam/option.{None, Some}
import gleeunit
import pog
import timeline
import timeline/availability.{Availability, OffShift, Travelling}
import timeline/db
import timeline/event.{
  ArrivedOnSite, DepartedSite, Event, ShiftEnded, ShiftStarted, TravelStarted,
}

pub fn main() -> Nil {
  gleeunit.main()
}

// --- Pure fold tests (no Postgres) -----------------------------------------
//
// PLAN.md "Data layer": "projection tables rebuilt from the log" — this is
// the rebuild logic itself, with no I/O involved, exercising
// `availability.project/1` directly over a hand-built event sequence.

pub fn project_full_shift_returns_to_off_shift_test() {
  let technician_id = "pure-fold-full-shift"

  let events = [
    Event(technician_id:, kind: ShiftStarted, occurred_at: 1, site_id: None),
    Event(
      technician_id:,
      kind: TravelStarted,
      occurred_at: 2,
      site_id: Some("site-a"),
    ),
    Event(
      technician_id:,
      kind: ArrivedOnSite,
      occurred_at: 3,
      site_id: Some("site-a"),
    ),
    Event(
      technician_id:,
      kind: DepartedSite,
      occurred_at: 4,
      site_id: Some("site-a"),
    ),
    Event(technician_id:, kind: ShiftEnded, occurred_at: 5, site_id: None),
  ]

  assert availability.project(events)
    == Availability(status: OffShift, site_id: None)
}

pub fn project_mid_shift_travelling_test() {
  let technician_id = "pure-fold-mid-shift"

  let events = [
    Event(technician_id:, kind: ShiftStarted, occurred_at: 1, site_id: None),
    Event(
      technician_id:,
      kind: TravelStarted,
      occurred_at: 2,
      site_id: Some("site-b"),
    ),
  ]

  assert availability.project(events)
    == Availability(status: Travelling, site_id: Some("site-b"))
}

pub fn project_of_empty_log_is_off_shift_test() {
  assert availability.project([]) == availability.initial()
}

// --- Live-Postgres test ------------------------------------------------
//
// Exercises the full round trip against the real `timeline` schema/role:
// appending events (timeline.append_*), rebuilding a projection from the
// sequence just appended (timeline.rebuild_availability), and querying the
// live availability projection directly (timeline.current_availability).
//
// gleeunit has no per-test transactional sandbox like ExUnit's
// Ecto.Adapters.SQL.Sandbox, so this test owns a dedicated technician_id
// and clears its own prior rows first, making repeat runs idempotent.

fn clear_technician(db: pog.Connection, technician_id: String) -> Nil {
  let assert Ok(_) =
    pog.query("delete from timeline.events where technician_id = $1")
    |> pog.parameter(pog.text(technician_id))
    |> pog.returning(decode.success(Nil))
    |> pog.execute(db)

  let assert Ok(_) =
    pog.query("delete from timeline.availability where technician_id = $1")
    |> pog.parameter(pog.text(technician_id))
    |> pog.returning(decode.success(Nil))
    |> pog.execute(db)

  Nil
}

pub fn append_rebuild_and_query_live_availability_test() {
  let technician_id = "gleam-test-append-rebuild-query"
  let assert Ok(conn) = db.connect()
  clear_technician(conn, technician_id)

  let assert Ok(Nil) = timeline.append_shift_started(technician_id, 1000)
  let assert Ok(Nil) =
    timeline.append_travel_started(technician_id, 1100, "site-42")
  let assert Ok(Nil) =
    timeline.append_arrived_on_site(technician_id, 1200, "site-42")

  let assert Ok(#(status, site_id)) =
    timeline.rebuild_availability(technician_id)
  assert status == "on_site"
  assert site_id == "site-42"

  // The live projection query, independent of the rebuild call above.
  let assert Ok(#(queried_status, queried_site_id)) =
    timeline.current_availability(technician_id)
  assert queried_status == "on_site"
  assert queried_site_id == "site-42"

  let assert Ok(Nil) = timeline.append_departed_site(technician_id, 1300, "site-42")
  let assert Ok(#(after_departure_status, after_departure_site_id)) =
    timeline.rebuild_availability(technician_id)
  assert after_departure_status == "on_shift"
  assert after_departure_site_id == ""
}

pub fn current_availability_before_any_rebuild_is_an_error_test() {
  let technician_id = "gleam-test-no-projection-yet"
  let assert Ok(conn) = db.connect()
  clear_technician(conn, technician_id)

  assert Error(
      "timeline: no availability projection yet for technician "
      <> technician_id,
    )
    == timeline.current_availability(technician_id)
}

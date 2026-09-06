//// Creates timeline's Postgres role, schema, and tables. Idempotent. Run
//// via `gleam run -m timeline/bootstrap` (see moon.yml).

import gleam/dynamic/decode
import gleam/io
import gleam/list
import pog
import timeline/db

const bootstrap_statements = [
  "do $$
   begin
     create role timeline login password 'timeline';
   exception when duplicate_object then
     raise notice 'role \"timeline\" already exists, skipping';
   end
   $$",
  "alter role timeline set search_path = timeline",
  "create schema if not exists timeline authorization timeline",
  "grant usage, create on schema timeline to timeline",
  "alter default privileges in schema timeline grant all on tables to timeline",
  "alter default privileges in schema timeline grant all on sequences to timeline",
  "revoke all on schema public from timeline",
]

const schema_statements = [
  "create table if not exists timeline.events (
     id bigserial primary key,
     technician_id text not null,
     kind text not null,
     occurred_at bigint not null,
     site_id text,
     inserted_at timestamptz not null default now()
   )",
  "create index if not exists events_technician_occurred_at_idx
     on timeline.events (technician_id, occurred_at)",
  "create table if not exists timeline.availability (
     technician_id text primary key,
     status text not null,
     site_id text,
     updated_at timestamptz not null default now()
   )",
]

fn run_all(db: pog.Connection, statements: List(String)) -> Nil {
  list.each(statements, fn(statement) {
    let assert Ok(_) =
      pog.query(statement)
      |> pog.returning(decode.success(Nil))
      |> pog.execute(db)
    Nil
  })
}

/// Creates the role/schema (as superuser), then the tables (as that role).
pub fn main() -> Nil {
  let assert Ok(superuser_db) = db.connect_superuser()
  run_all(superuser_db, bootstrap_statements)
  io.println("timeline.bootstrap: role \"timeline\" + schema \"timeline\" ready")

  let assert Ok(timeline_db) = db.connect()
  run_all(timeline_db, schema_statements)
  io.println("timeline.bootstrap: tables ready")
}

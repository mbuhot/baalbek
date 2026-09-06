//// Postgres connections for `timeline`, via `pog`. Connection details are
//// fixed to match `.devcontainer/docker-compose.yml`'s `postgres` service,
//// not read from environment variables.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process
import gleam/option.{Some}
import gleam/otp/actor
import pog

@external(erlang, "persistent_term", "get")
fn persistent_term_get(
  key: atom.Atom,
  default: Result(pog.Connection, actor.StartError),
) -> Result(pog.Connection, actor.StartError)

@external(erlang, "persistent_term", "put")
fn persistent_term_put(
  key: atom.Atom,
  value: Result(pog.Connection, actor.StartError),
) -> Nil

// Starts pgo's application (its query-plan cache ETS table is otherwise
// never created, since timeline isn't a declared OTP dependency of
// whatever loads it).
@external(erlang, "application", "ensure_all_started")
fn ensure_all_started(application: atom.Atom) -> Dynamic

// pog.start links the pool to its caller permanently. Unlinking avoids
// the pool dying when a short-lived caller (an ExUnit test process) later
// exits abnormally.
@external(erlang, "erlang", "unlink")
fn unlink(pid: process.Pid) -> Bool

fn start_pool(
  user: String,
  password: String,
) -> Result(pog.Connection, actor.StartError) {
  ensure_all_started(atom.create("pgo"))

  let name = process.new_name("timeline_pg_" <> user)

  let config =
    pog.default_config(pool_name: name)
    |> pog.host("localhost")
    |> pog.port(5432)
    |> pog.database("baalbek")
    |> pog.user(user)
    |> pog.password(Some(password))
    |> pog.pool_size(2)

  case pog.start(config) {
    Ok(started) -> {
      unlink(started.pid)
      Ok(started.data)
    }
    Error(error) -> Error(error)
  }
}

/// One pool per role, memoized for the running VM's lifetime.
fn connect_as(
  user user: String,
  password password: String,
) -> Result(pog.Connection, actor.StartError) {
  let cache_key = atom.create("timeline_pg_conn_" <> user)
  let uncached = Error(actor.InitFailed("timeline: no cached connection yet"))

  case persistent_term_get(cache_key, uncached) {
    Error(actor.InitFailed("timeline: no cached connection yet")) -> {
      let result = start_pool(user, password)
      persistent_term_put(cache_key, result)
      result
    }
    cached -> cached
  }
}

/// Connects as the unprivileged `timeline` role — the only role
/// application code should use.
pub fn connect() -> Result(pog.Connection, actor.StartError) {
  connect_as(user: "timeline", password: "timeline")
}

/// Connects as the Postgres superuser, for `bootstrap.gleam` only.
pub fn connect_superuser() -> Result(pog.Connection, actor.StartError) {
  connect_as(user: "postgres", password: "postgres")
}

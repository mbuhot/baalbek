-- Bootstrap for `core`'s Postgres role + schema (PLAN.md "Data layer":
-- "One database role per component, granted only on its own schema" /
-- seed.md §5: "Enforcement is role-based... a cross-boundary query is a
-- hard error, not a convention.").
--
-- This is a *structural* setup step, distinct from Ecto migrations: it
-- must run once per Postgres cluster/database as a superuser (the `core`
-- role itself has no privilege to create roles or schemas), before
-- `mix ecto.migrate` (or `mix core.bootstrap && mix ecto.migrate`) can
-- create `core`'s tables inside schema `core`.
--
-- Run it either:
--   * by hand:      psql -U postgres -d baalbek -f priv/repo/bootstrap.sql
--   * or scripted:  mix core.bootstrap
--     (lib/mix/tasks/core.bootstrap.ex reads this exact file and executes
--     it statement-by-statement over a Postgrex connection using
--     superuser credentials — no separate copy of this SQL is maintained
--     in Elixir source, so the two invocation paths can never drift).
--
-- Idempotent: safe to run against a database that already has some or all
-- of this in place (CI, a rebuilt devcontainer, a second developer).
--
-- Statement separator convention: each statement below ends with a line
-- containing only ";" — see lib/mix/tasks/core.bootstrap.ex's header
-- comment for why (a naive top-level split on every ";" would misfire
-- inside the DO block's dollar-quoted body).
--
-- Concurrency: a from-scratch Postgres running core's, identity's, and
-- billing's bootstraps concurrently (as CI, or a fresh devcontainer,
-- does) hits Postgres's well-known concurrent-DDL-on-shared-catalog
-- failure: `CREATE ROLE` writes the cluster-wide `pg_authid` catalog, and
-- `REVOKE ALL ON SCHEMA public FROM core` is a read-modify-write of the
-- *same* `pg_namespace` row for `public` that identity's and billing's
-- bootstraps also read-modify-write for their own roles. Two sessions
-- racing on that path surfaces as `Postgrex.Error: tuple concurrently
-- updated` — not deterministic, since it depends on how the sessions
-- interleave.
--
-- Fix: hold a session-level Postgres advisory lock for the whole script,
-- so concurrent bootstraps queue instead of racing. The lock id
-- (726352001) is an arbitrary constant, but it MUST be the exact same
-- constant in every component's bootstrap.sql that touches this database
-- (identity's and billing's bootstrap.sql already use it) — a different
-- id per component would let them race again, defeating the point.
SELECT pg_advisory_lock(726352001)
;

DO $$
BEGIN
  CREATE ROLE core LOGIN PASSWORD 'core';
EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'role "core" already exists, skipping';
END
$$
;

-- Every session opened as `core` resolves unqualified table names inside
-- schema `core` without needing `search_path` set per-connection by Ecto —
-- this is what lets Core.Data.Repo's migrations/queries omit a schema
-- prefix entirely.
ALTER ROLE core SET search_path = core
;

CREATE SCHEMA IF NOT EXISTS core AUTHORIZATION core
;

-- `core` owning its own schema already implies full rights inside it; the
-- explicit grants below are belt-and-braces documentation of intent and
-- keep this idempotent (re-running GRANT is always safe) regardless of
-- whether AUTHORIZATION above already covered it.
GRANT USAGE, CREATE ON SCHEMA core TO core
;

ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT ALL ON TABLES TO core
;

ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT ALL ON SEQUENCES TO core
;

-- Structural isolation, not convention (seed.md §5): `core` cannot
-- resolve unqualified objects in `public`, so a query that leaks past
-- this component's own schema is a hard error rather than something that
-- happens to work today.
REVOKE ALL ON SCHEMA public FROM core
;

-- Release the lock taken at the top of this script. If an earlier
-- statement raised (this DO $$ block already catches the one expected
-- exception; anything else would abort the script), this line is never
-- reached — but the connection this script runs over (opened fresh by
-- mix core.bootstrap, or a one-shot `psql -f`) then closes anyway, and
-- Postgres releases every advisory lock held by a session automatically
-- when that session ends, so the lock can't leak.
SELECT pg_advisory_unlock(726352001)
;

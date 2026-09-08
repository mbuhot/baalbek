-- Bootstrap for `identity`'s Postgres role and schema: one role per component,
-- granted only on its own schema, so a cross-boundary query is a hard error
-- rather than a convention. core/priv/repo/bootstrap.sql is the same script
-- with core in place of identity.
--
-- This is a *structural* setup step, distinct from Ecto migrations: it
-- must run once per Postgres cluster/database as a superuser (the
-- `identity` role itself has no privilege to create roles or schemas),
-- before `mix ecto.migrate` (or `mix identity.bootstrap && mix
-- ecto.migrate`) can create `identity`'s tables inside schema `identity`.
--
-- Run it either:
--   * by hand:      psql -U postgres -d baalbek -f priv/repo/bootstrap.sql
--   * or scripted:  mix identity.bootstrap
--     (lib/mix/tasks/identity.bootstrap.ex reads this exact file and
--     executes it statement-by-statement over a Postgrex connection using
--     superuser credentials — no separate copy of this SQL is maintained
--     in Elixir source, so the two invocation paths can never drift).
--
-- Idempotent: safe to run against a database that already has some or all
-- of this in place (CI, a rebuilt devcontainer, a second developer).
--
-- Statement separator convention: each statement below ends with a line
-- containing only ";" — see lib/mix/tasks/identity.bootstrap.ex's header
-- comment for why (a naive top-level split on every ";" would misfire
-- inside the DO block's dollar-quoted body).
--
-- Concurrency: `moon run identity:test billing:test` (this stage's own
-- gate) fans identity's and billing's bootstraps out to run concurrently
-- against the same `baalbek` database, and a from-scratch CI Postgres hits
-- this every time. Every statement below mutates state Postgres treats as
-- shared across the whole database, not scoped to `identity`'s own role/
-- schema: `CREATE ROLE` writes the cluster-wide `pg_authid` catalog, and
-- `REVOKE ALL ON SCHEMA public FROM identity` is a read-modify-write of
-- the *same* `pg_namespace` row for `public` that billing's (or any other
-- component's) bootstrap also read-modify-writes for its own role. Two
-- sessions racing on that path is exactly Postgres's well-known
-- concurrent-DDL-on-shared-catalog failure, surfaced as a
-- `Postgrex.Error: tuple concurrently updated` — not a defect in this
-- script's own logic, and not deterministic (it depends on how the two
-- sessions interleave), which is why it didn't reproduce on every run.
--
-- Fix: hold a session-level Postgres advisory lock for the whole script,
-- so two concurrent bootstraps queue instead of racing. This is a
-- database-scoped lock (keyed by the advisory-lock id within whatever
-- database the session is connected to), which is exactly right here:
-- both identity's and billing's bootstrap connect to the same `baalbek`
-- database (BOOTSTRAP_PG_DATABASE), so the same lock id serializes them
-- against each other. The lock id (726352001) is an arbitrary constant,
-- but it MUST be the exact same constant in every component's
-- bootstrap.sql that touches this database — a different id per
-- component would let them race again, defeating the point. `core`'s
-- own bootstrap.sql now uses the same lock id, so all three components'
-- bootstraps serialize against each other, not just pairwise.
SELECT pg_advisory_lock(726352001)
;

DO $$
BEGIN
  CREATE ROLE identity LOGIN PASSWORD 'identity';
EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'role "identity" already exists, skipping';
END
$$
;

-- Every session opened as `identity` resolves unqualified table names
-- inside schema `identity` without needing `search_path` set
-- per-connection by Ecto — this is what lets Identity.Repo's
-- migrations/queries omit a schema prefix entirely.
ALTER ROLE identity SET search_path = identity
;

CREATE SCHEMA IF NOT EXISTS identity AUTHORIZATION identity
;

-- `identity` owning its own schema already implies full rights inside it;
-- the explicit grants below are belt-and-braces documentation of intent
-- and keep this idempotent (re-running GRANT is always safe) regardless
-- of whether AUTHORIZATION above already covered it.
GRANT USAGE, CREATE ON SCHEMA identity TO identity
;

ALTER DEFAULT PRIVILEGES IN SCHEMA identity GRANT ALL ON TABLES TO identity
;

ALTER DEFAULT PRIVILEGES IN SCHEMA identity GRANT ALL ON SEQUENCES TO identity
;

-- Structural isolation, not convention: `identity` cannot
-- resolve unqualified objects in `public`, so a query that leaks past
-- this component's own schema is a hard error rather than something that
-- happens to work today.
REVOKE ALL ON SCHEMA public FROM identity
;

-- Release the lock taken at the top of this script. If an earlier
-- statement raised (this DO $$ block already catches the one expected
-- exception; anything else would abort the script), this line is never
-- reached — but the connection this script runs over (opened fresh by
-- mix identity.bootstrap, or a one-shot `psql -f`) then closes anyway,
-- and Postgres releases every advisory lock held by a session
-- automatically when that session ends, so the lock can't leak.
SELECT pg_advisory_unlock(726352001)
;

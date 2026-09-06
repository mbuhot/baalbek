# ADR-0003: The pnpm workspace has no root `package.json`

**Status:** Accepted
**Date:** 2026-09-06
**Stage:** 6

## Context

`web` and `core-api-client` are pnpm workspace members. Almost every pnpm
workspace in the wild also carries a root `package.json` — it is what npm and
Yarn require, and most tooling documentation assumes it.

A root `package.json` in this repo would be a fifteenth project that isn't a
component: it would attract shared devDependencies, root-level scripts, and
eventually a root `node_modules` that TypeScript, ESLint, and Vite all
resolve through. That is exactly the JS-first monorepo shape seed.md §1
rejected Turborepo for. The Elixir, Rust, and Gleam projects would gain a
JavaScript manifest above them that says nothing about them.

## Decision

No root `package.json`. `pnpm-workspace.yaml` alone declares the workspace;
each TypeScript project owns its own manifest, its own dependencies, and its
own scripts. Shared TypeScript compiler options live in
`config/tsconfig.base.json` — a plain configuration file, not a package.

## Consequences accepted

- Every pnpm command runs with a `--filter`, or from inside the project
  directory. There is no root `pnpm run <script>`, and there is no place to
  hang one.
- Tooling that assumes a root manifest has to be pointed at a project
  instead. This was verified rather than assumed: `pnpm install`,
  `pnpm --filter web run <script>`, and every Moon task work with no root
  manifest present.
- Shared dependency versions are not deduplicated by a root manifest. With
  two TypeScript projects that is not a cost worth a root package for; with
  ten it might be, and this ADR should be superseded then.

## Alternatives considered

**A root `package.json` with `private: true` and no dependencies.** The
minimal version of the thing being avoided. Rejected because it does not stay
minimal — it is the obvious place to put the next shared devDependency, and
the JS-first gravity starts there.

**Moon-level tasks instead of pnpm scripts.** Already the case for anything
CI runs; each project's `moon.yml` is the entry point. The scripts inside
each `package.json` exist for local iteration, which is a per-project
concern.

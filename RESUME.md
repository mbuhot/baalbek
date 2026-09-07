# Resume here

Temporary. Delete this file once the work below is picked up.

## The prompt to resume with

> Read RESUME.md. The sandbox has been recreated to fix a virtiofs corruption
> bug. First re-run the corruption probe in "Verify the environment fix" and
> report the result. Then continue the moon.yml simplification goal from
> "What is left", smallest item first.

## Where things stand

Two goals ran to near-completion. Everything described is committed and pushed
to `main`.

### CI speed-up (complete)

| Item | Outcome |
|---|---|
| GHCR image cache | Done: image step 2m 48s to 62s |
| `moon ci` on the runner | Measured and **rejected**: 22m 6s native against 24m 26s image, and each shape failed a task the other passed (ADR-0009) |
| Third-party `deps` task | Done: `billing:deps` 6m 42s cold to 1.97s cached |
| `actions/cache` reuse | Done: `main`'s cache 5 MB to 198 MB once `deps/` became a declared output |
| Guard rails | Done: `implicitInputs`, and a nightly whole-graph run from a cold cache |
| Small wins | pnpm store already correct; Postgres pinned once in `.devcontainer/.env` |

Proved with six merged pull requests (#1 to #6) plus #7 closed after
measurement. A one-line Elixir change cost 12m 15s before and 5m 12s after.
A docs-only change resolves 0 targets.

Two defects the exercise found, both fixed: `moon ci` compared changed files
only, so no consumer of a changed library was ever tested until
`--include-relations` was added alongside `--downstream deep` (ADR-0011); and
`main` published progressively sparser caches that shadowed richer ones, until
it was made to run the whole graph cold.

### moon.yml simplification (nearly complete)

1171 lines across 18 files became 831, and `description` prose went 309 lines
to 21. `pnpm install --frozen-lockfile` appears once instead of nine times.

Landed in order: `715259f` (Hex `ash_boundary`, deleting the workaround it
forced), `7126aca` (Rust, Gleam, mobile, root), `ff6ebb5` (TypeScript),
`f6ac334` (shared Elixir bootstrap), `39768a5` (timeline toolchain).

## What is left

1. **`.moon/tasks/elixir-repo.yml`.** `bootstrap-repo` is `internal: true` in
   `.moon/tasks/elixir.yml`, and `core`, `identity` and `billing` each opt back
   in with `options: {internal: false}`. That is a workaround: `inheritedBy` is
   AND-only and file-scoped, so one task inside a template cannot be gated.
   The right shape is a second template conditioned on
   `{language: elixir, file: priv/repo/bootstrap.sql}` — the pattern
   `.moon/tasks/typescript.yml` already uses to stay off `config`. Removes
   `internal` and about 15 lines. It lands in `implicitInputs`' `/.moon/tasks/*.yml`
   glob, so it invalidates every task once.
2. **`explorer/src/generated/model.json` is stale** — it still embeds the old
   long task descriptions and has no `bootstrap-repo`. Run `moon run
   explorer:generate` and commit.
3. **`mobile/moon.yml` and the root `moon.yml`** each declare
   `toolchain: "system"` on every task, which may be redundant as it was for
   `timeline`. My probe compared the wrong target and I left them rather than
   trust it. Verify with `moon task <target>` before and after.
4. **`root:sandbox-image` and `server:image` use `bash -lc` for a pure `docker`
   command.** `docker` is at `/usr/bin/docker` and needs no login shell, but
   PATH inside the CI sandbox image was never measured. Measure, then simplify
   both or neither.
5. **`cargo fmt --check` fails in `moon-elixir-plugin`** with pre-existing
   diffs, and nothing gates it.

## Verify the environment fix

The sandbox was recreated with `DOCKER_SANDBOXES_ENABLE_VIRTIOFS_CACHE=0` to
fix silent file corruption. `cp` served stale cached pages while `read`
revalidated, so `copy_file_range` returned wrong bytes at the right length.
Reproduced twice at **540 of 596 files**; `tar` was correct 596 of 596.

```sh
src=timeline/build/erlang-shipment          # moon run timeline:build if absent
rm -rf /tmp/t /tmp/c && mkdir -p /tmp/t /tmp/c
for a in $(ls -1 $src); do tar -C $src -cf - "$a" | tar -C /tmp/t -xf -; done
for a in $(ls -1 $src); do cp -R "$src/$a" /tmp/c/; done
diff -r /tmp/t /tmp/c | wc -l               # 0 means fixed
```

If it reports 0, three workarounds become dead weight and should go in one
commit citing the before and after: `pricing/moon.yml` using `cat` rather than
`cp`, `timeline/scripts/package-otp.sh` using `tar` rather than `cp -R`, and
the `EEXIST` comment above `CARGO_TARGET_DIR` in `pricing/moon.yml`. Keep the
`CARGO_TARGET_DIR` redirection itself: `pricing_native`'s `native/**/*` input
glob covers the in-tree `target/`, and CI caches that path.

If it still reports about 540, the variable did not work. The alternatives are
the 35 named volumes `.devcontainer/docker-compose.yml` already mounts over
every build directory, or `sbx --clone`.

Case-insensitivity is **not** fixed by any of this. It is the host filesystem,
and `CLAUDE.md`'s rule stands: never delete an apparent case-duplicate.

## Things that cost time to learn

- A warm project graph hides defects. The plugin reads a manifest while moon
  builds the graph, so `timeline_facade` reported one path dependency cold and
  eleven warm. Gates must clear build trees, `.moon/cache/states`, `hashes`
  **and** `outputs`, or tasks replay and suites never execute.
- A project-declared task **merges** with the inherited one; every merge
  strategy defaults to append. A plugin-supplied task is the case that replaces.
- moon dereferences symlinks when it archives. `node_modules` must not be a
  declared output: it would freeze a copy of the generated API client and let
  `web:build` type-check green against a stale schema.
- moon refuses to archive a nested `.git/`, which is why a git dependency broke
  restored trees and a Hex one does not.

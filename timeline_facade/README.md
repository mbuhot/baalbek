# timeline_facade

**Language:** Elixir

**Purpose:** Sole caller of the Gleam `timeline` modules; `boundary`-enforced
for calls within this app (see the ADR for why `boundary` can't police the
`:timeline` edge itself, and the compensating check in moon.yml).

## Local setup

```bash
docker compose -f ../.devcontainer/docker-compose.yml up -d postgres
cd ../timeline && gleam run -m timeline/bootstrap && bash scripts/package-otp.sh
cd ../timeline_facade && mix deps.get && mix test
```

Or via Moon: `moon run timeline:test timeline_facade:test`.

`mix.exs` declares one Mix path dependency per OTP application in
`../timeline/build/otp`, from a list written out in `@timeline_otp_apps`. The
list is the same answer before and after `timeline:build` has written that
directory, because moon-elixir-plugin reads it while it builds the project
graph and the `dependsOn` it infers is whatever the manifest says then;
`check_shipment!/0` fails the manifest when the list and the directory
disagree. See
`../spec/decisions/adr-0010-third-party-deps-compile-in-their-own-task.md`.
See `../server/spec/decisions/adr-0001-release-assembly-and-gleam-packaging.md`
for why that shape, and `spec/decisions/adr-0001-gleam-elixir-interop.md` (now
superseded) for the Stage 5 mechanism it replaced.

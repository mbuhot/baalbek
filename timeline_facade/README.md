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
`../timeline/build/otp`, so `mix.exs` raises if `timeline:package` has not run.
See `../server/spec/decisions/adr-0001-release-assembly-and-gleam-packaging.md`
for why that shape, and `spec/decisions/adr-0001-gleam-elixir-interop.md` (now
superseded) for the Stage 5 mechanism it replaced.

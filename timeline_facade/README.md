# timeline_facade

**Language:** Elixir

**Purpose:** Sole caller of the Gleam `timeline` modules; `boundary`-enforced
for calls within this app (see the ADR for why `boundary` can't police the
`:timeline` edge itself, and the compensating check in moon.yml).

## Local setup

```bash
docker compose -f ../.devcontainer/docker-compose.yml up -d postgres
cd ../timeline && gleam run -m timeline/bootstrap && gleam build
cd ../timeline_facade && mix deps.get && mix test
```

Or via Moon: `moon run timeline:test timeline_facade:test`.

See `docs/adr-0001-gleam-elixir-interop.md` for how this project loads
timeline's compiled Gleam output with no Mix dependency between them.

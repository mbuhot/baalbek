# ADR-0004: Gherkin acceptance specs run on `cucumber`, from `spec/features/`

**Status:** Accepted
**Date:** 2026-09-06
**Stage:** 8

## Context

seed.md §7.5 asks for Gherkin feature files in the repo, wired to ExUnit, and
is explicit that the wiring library is a swappable detail — the requirement
is specs that fail when behaviour changes. §8 puts those feature files in
each component's `spec/features/`, alongside its mocks and decisions, so an
agent or a new engineer gets criteria, intent, and structure in one place.

Elixir's options here are thinner than Ruby's Cucumber, and most of them are
abandoned:

| Package | Last release | Notes |
|---|---|---|
| `white_bread` | 4.5.0, January 2019 | Seven years stale. Not considered further. |
| `cabbage` | 0.4.1, September 2023 | Works, `gherkin ~> 2.0` parser, but three years since a release and its declared floor is Elixir 1.13. |
| `cucumber` | 1.0.0, July 2026 | [huddlz-hq/cucumber](https://github.com/huddlz-hq/cucumber). Elixir `~> 1.18`. Passes the official Cucumber Compatibility Kit. |

## Decision

Use `cucumber` 1.0. Feature files live in each component's
`spec/features/*.feature`; step definitions and hooks live beside them in
`spec/features/step_definitions/` and `spec/features/support/`, and are
loaded by `Cucumber.compile_features!/1` from that component's
`test/test_helper.exs`.

`core`, `identity`, `billing`, and `server` carry features. The two facade
apps do not: `pricing_native` and `timeline_facade` exist to expose one
foreign artefact each, and have no domain behaviour to state in a
stakeholder's language.

`timeline` and `pricing` are a different case, and a less comfortable one.
Both have real domain behaviour a stakeholder would recognise — event-sourced
shift and travel events resolving to an availability projection, and a quote
built from travel, labour, and parts — so both would benefit from acceptance
criteria. They have none because this wiring runs on ExUnit, which reaches
only Elixir: `timeline` is Gleam with a `gleeunit` suite, `pricing` is Rust
with `cargo test`. Neither gap is a judgement that the behaviour is not worth
specifying. The nearest honest coverage is indirect — `timeline_facade`'s and
`pricing_native`'s ExUnit suites call through to the real compiled artefacts
— and a component-language-native BDD runner, or Gherkin features driven
through the facades, would close it properly. Recorded here so the omission
reads as a known limit of the wiring rather than an oversight.

## Why this library

It is the only maintained option, and its maintenance is recent rather than
merely non-zero (four releases in the eight months to July 2026). CCK
compliance matters more than it first appears: the compatibility kit is the
reference implementation's own approval suite, so "Gherkin" here means the
real grammar — `Rule:`, scenario outlines, data tables, docstrings, tags —
rather than a subset that will diverge from what a business analyst writes.

Its dependency footprint is one library (`nimble_parsec`), and it generates
plain ExUnit test modules, so the specs run inside the existing `mix test`
and the existing Moon `test` task with no separate runner, no separate CI
step, and no separate reporting.

## Consequences accepted

- **Features are not path-selectable.** `Cucumber.compile_features!/1` runs
  in `test_helper.exs`, which ExUnit always evaluates, so the acceptance
  specs run on every `mix test` — including `mix test.changed`
  (adr-0005). This is defensible rather than merely tolerated: the acceptance
  specs are the behavioural guard rail, they are fast, and running them
  always is what "specs that fail when behaviour changes" means. `mix test
  --only cucumber` runs them alone when that is what is wanted.
- **Steps are code that only the spec uses.** They are exercised solely by
  the features they serve, so a stale step definition rots silently. Keeping
  them inside `spec/features/` rather than under `test/` at least puts the
  rot in one visible place.
- **Swapping the library means rewriting the step files, not the features.**
  The `.feature` files are plain Gherkin; the `step`/`before_scenario` macros
  are the library-specific part. That is the seam seed.md's "swappable
  detail" language implies, and it is where a replacement would land.

## Verified

The specs fail when behaviour changes, not merely when they are wrong: with
`billing`'s `HasLineItems` validation removed from the `issue` action, the
"An invoice with no charge lines cannot be issued" scenario fails under
`mix test --only cucumber`, with the unit suite excluded.

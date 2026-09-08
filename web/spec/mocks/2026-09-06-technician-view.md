# Technician view — 2026-09-06

Snapshot of intent at build time. See `README.md`: not maintained,
not authoritative.

## Layout

```
┌────────────────────────────────────────────────────────────────────────────┐
│  Baalbek Dispatch                                                          │
│                                                                            │
│  ( Dispatch board )  [ Technician view ]                                   │
│                                                                            │
│  My work queue (simplified — not filtered by technician)                   │
│  ┌────────────────────┬──────────────┬───────────────────┬────────────────┐│
│  │ Work order         │ Status       │ Job               │ Completed      ││
│  ├────────────────────┼──────────────┼───────────────────┼────────────────┤│
│  │ Initial visit      │ in_progress  │ Fix conveyor      │ —              ││
│  │ Follow-up visit    │ open         │ Fix conveyor      │ —              ││
│  │ Quarterly check    │ completed    │ Quarterly service │ 2 Sep 14:30    ││
│  └────────────────────┴──────────────┴───────────────────┴────────────────┘│
└────────────────────────────────────────────────────────────────────────────┘
```

## Intent

- **The technician's own queue, on a phone.** This is the view the Capacitor
  wrapper ships; a single scrollable list, no side navigation, no filters.
- **Open and in-progress work first**, completed work below it. A technician
  opens this to find the next job, not to review finished ones.
- **The caption states the simplification out loud.** `identity` has no HTTP
  surface yet, so there is no per-technician assignment to filter on, and the
  view lists every open work order instead. Saying so in the UI was a
  deliberate choice over quietly showing everyone's work as if it were one
  technician's, or fabricating technician data to make the mock look
  finished. When `identity` grows an HTTP surface, the filter arrives and the
  caption goes.
- **Job title on every row**, because a work-order summary alone
  ("Initial visit") does not say what the work is.

## States

| State | Shown |
|---|---|
| Loading | `Loading work queue…` |
| Request failed | The error text, as an alert |
| No work orders | `No work orders yet.` |

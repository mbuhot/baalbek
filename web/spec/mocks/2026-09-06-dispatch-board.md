# Dispatch board — 2026-09-06

Snapshot of intent at build time (Stage 6). See `README.md`: not maintained,
not authoritative.

## Layout

```
┌────────────────────────────────────────────────────────────────────────────┐
│  Baalbek Dispatch                                                          │
│                                                                            │
│  [ Dispatch board ]  ( Technician view )        <- tabs, current is pressed│
│                                                                            │
│  Dispatch board                                            <- table caption│
│  ┌──────────────────┬────────────┬──────────────────┬───────────┬─────────┐│
│  │ Job              │ Status     │ Scheduled        │ Site      │ Customer││
│  ├──────────────────┼────────────┼──────────────────┼───────────┼─────────┤│
│  │ Fix conveyor     │ scheduled  │ 6 Sep 2026 09:00 │ Warehouse │ Acme    ││
│  │ Replace bearing  │ requested  │ —                │ Warehouse │ Acme    ││
│  │ Quarterly service│ completed  │ 2 Sep 2026 14:30 │ Depot 4   │ Widgets ││
│  └──────────────────┴────────────┴──────────────────┴───────────┴─────────┘│
└────────────────────────────────────────────────────────────────────────────┘
```

## Intent

- **One row per job, every job.** A dispatcher planning the week wants the
  whole board, not a filtered slice. Filtering and sorting were discussed and
  deliberately left out of the first build.
- **Site and customer are shown on the job row**, because "which customer is
  this for" is the question a dispatcher asks before touching anything else.
  The API returns no relationship between these resources, so the join is
  client-side.
- **An unresolvable site or customer reads "Unknown site" / "Unknown
  customer"**, never a blank cell. A blank looks like missing data; the word
  says the join failed.
- **`—` for an unscheduled job**, not an empty cell, for the same reason.
- **Status is the raw domain word** (`requested`, `scheduled`, `in_progress`,
  `completed`, `cancelled`). Dispatchers use these words; translating them
  into friendlier prose was considered and rejected as it would diverge from
  what `core` reports.

## States

| State | Shown |
|---|---|
| Loading | `Loading dispatch board…` |
| Request failed | The error text, as an alert |
| No jobs | `No jobs yet.` |

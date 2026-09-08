# UI mock snapshots

Dated snapshots of what each view was *meant* to be when it was built.
Read them as history, never as a specification.

## The lifecycle these files are part of

Mock iteration happens **outside this repo**, in lightweight tooling — Figma,
or Storybook assembled from the real components — with PMs and designers.
That is where a mock is cheap to change, and cheap is the whole point of it.

When a view is built, one snapshot of the mock is committed here, named by
the date it was taken. Nothing updates it afterwards. The mock is never the
source of truth: the durable asset is the component library it was assembled
from, and the enforced contract is `spec/features/` plus the generated
`core-api-client` types. The moment a mock becomes authoritative it stops
being cheap, and it loses the only property that made it worth keeping.

So a snapshot older than the code is not a defect to fix. It is a record of
the intent the code was built against, which is exactly what someone reading
the code six months later cannot otherwise recover.

## What is here, and what would be

The snapshots in this directory are committed **wireframes in Markdown** —
layout, fields, states, and the copy that carries meaning. They are the real
artefact for this repo, not stand-ins for one: this reference project has no
design tool attached to it, and a wireframe at this fidelity is what the
dispatch board's intent actually amounted to.

In a client engagement the same files would be PNG or PDF exports from the
design tool, named the same way (`YYYY-MM-DD-<view>.png`), with the same
lifecycle. Nothing else about this directory changes.

## Naming

`YYYY-MM-DD-<view>.md` — the date the snapshot was taken, then the view it
shows. A second snapshot of the same view gets a new date and a new file; the
old one stays.

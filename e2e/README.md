# e2e

**Language:** Playwright

**Purpose:** Depends on `server` + `web` builds.

Full run on main and nightly as the backstop; selection is a fast pre-merge
gate, never the final word. No deploy without the full e2e suite green.
Skeleton only (Stage 0) — no `package.json` or `moon.yml` yet; those land in
Stage 1 and Stage 9.

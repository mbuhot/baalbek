#!/usr/bin/env python3
"""Fail the build if a component's declared Moon `dependsOn` drifts from its
Mix path dependencies.

Why this exists (seed.md §2, "Fallback"):

    Until the plugin exists, declare `dependsOn` manually and add a CI check
    that diffs declared deps against `mix.exs` path deps (a small script),
    so drift fails the build rather than corrupting affected-detection.

Stage 1 (PLAN.md) wires this up as a Moon task — `root:check-deps-drift`,
run via `moon run :check-deps-drift` (or swept up for free by
`moon check --all`) — before any `mix.exs` files exist. At Stage 1 it finds
zero Elixir apps and passes trivially; from Stage 2 onward, every Elixir app
added under this repo root gets checked automatically, no script changes
required.

Stage 11 replaces this script with moon-elixir-plugin (a WASM toolchain
plugin that parses mix.exs natively); this script is the bridge until then.

What it checks
---------------
For every direct subdirectory of the repo root that contains a `mix.exs`:

  1. Parse that mix.exs for path dependencies, i.e. entries shaped like
     `{:some_app, path: "../some_app"}`. The resolved path's final
     component is the dependency's *project id* (its directory name, which
     is also its Moon project id given this repo's flat layout).
  2. Parse that project's `moon.yml` for its declared top-level
     `dependsOn:` list.
  3. Compare the two, but ONLY over targets that are themselves Elixir
     projects (i.e. also have a mix.exs) — a project may legitimately
     declare a `dependsOn` on a non-Mix, cross-language project (e.g.
     pricing_native -> pricing (Rust), timeline_facade -> timeline
     (Gleam); see PLAN.md "Two facades, one pattern"). Those edges are not
     Mix path deps and are intentionally left alone by this script.

Drift (an Elixir path dep with no matching `dependsOn`, or a declared
Elixir-to-Elixir `dependsOn` with no matching path dep) fails loudly with a
non-zero exit and a human-readable diff.

No third-party dependencies (no PyYAML): `dependsOn` is a simple top-level
YAML list of quoted/bare strings, and mix.exs path deps are simple Elixir
tuple literals, so both are parsed with small, deliberately narrow regexes
rather than a full YAML/Elixir parser. If a future mix.exs or moon.yml uses
a shape these regexes don't recognize, this script should be widened
alongside it (or retired early in favour of Stage 11's real parser).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent

# Matches `path: "../foo"` or `path: "foo/bar"` inside a mix.exs deps entry.
MIX_PATH_DEP_RE = re.compile(r'path:\s*"([^"]+)"')

# Matches a top-level `dependsOn:` YAML block and captures its list items
# (each a `- foo`, `- "foo"`, or `- 'foo'` line) up to the next top-level
# (non-indented, non-blank, non-comment) key or end of file.
DEPENDS_ON_BLOCK_RE = re.compile(
    r"^dependsOn:\s*\n((?:[ \t]+.*\n?|[ \t]*\n)*)", re.MULTILINE
)
LIST_ITEM_RE = re.compile(r'^\s*-\s*[\'"]?([^\'"\s#]+)[\'"]?\s*$', re.MULTILINE)


def find_project_dirs() -> list[Path]:
    """Direct subdirectories of the repo root, excluding dotdirs — mirrors
    the `globs: ["*"]` project source pattern in .moon/workspace.yml."""
    return sorted(
        p for p in REPO_ROOT.iterdir() if p.is_dir() and not p.name.startswith(".")
    )


def parse_mix_path_deps(mix_exs: Path) -> set[str]:
    text = mix_exs.read_text(encoding="utf-8")
    ids = set()
    for raw_path in MIX_PATH_DEP_RE.findall(text):
        ids.add(Path(raw_path).name)
    return ids


def parse_declared_depends_on(moon_yml: Path) -> set[str]:
    if not moon_yml.exists():
        return set()
    text = moon_yml.read_text(encoding="utf-8")
    match = DEPENDS_ON_BLOCK_RE.search(text)
    if not match:
        return set()
    return set(LIST_ITEM_RE.findall(match.group(1)))


def main() -> int:
    project_dirs = find_project_dirs()
    elixir_projects = {p.name: p for p in project_dirs if (p / "mix.exs").exists()}

    if not elixir_projects:
        print(
            "check-deps-drift: no mix.exs files found yet (expected pre-Stage 2) "
            "— nothing to check, passing trivially."
        )
        return 0

    elixir_ids = set(elixir_projects)
    had_drift = False

    for project_id, project_dir in sorted(elixir_projects.items()):
        mix_deps = parse_mix_path_deps(project_dir / "mix.exs")
        declared = parse_declared_depends_on(project_dir / "moon.yml")

        # Only reconcile the Elixir-to-Elixir slice of dependsOn — a
        # dependsOn pointing at a non-Mix project (Rust crate, Gleam
        # package, ...) is a legitimate declared cross-language edge, not a
        # Mix path dep, and is out of scope for this check by design.
        declared_elixir = declared & elixir_ids

        missing_from_moon = mix_deps - declared_elixir
        extra_in_moon = declared_elixir - mix_deps

        if missing_from_moon or extra_in_moon:
            had_drift = True
            print(f"check-deps-drift: DRIFT in {project_id}")
            if missing_from_moon:
                print(
                    f"  mix.exs has path dep(s) not in moon.yml dependsOn: "
                    f"{sorted(missing_from_moon)}"
                )
            if extra_in_moon:
                print(
                    f"  moon.yml dependsOn declares Elixir project(s) with no "
                    f"matching mix.exs path dep: {sorted(extra_in_moon)}"
                )

    if had_drift:
        print(
            "check-deps-drift: FAILED — declared dependsOn and mix.exs path "
            "deps disagree (see above). Fix moon.yml or mix.exs so they match."
        )
        return 1

    print(f"check-deps-drift: OK — {len(elixir_projects)} Elixir project(s) checked, no drift.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

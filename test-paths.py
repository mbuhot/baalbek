#!/usr/bin/env python3
"""Own the `lib/<area>` to `test/<area>` mirroring convention for every Elixir app.

Why this exists (seed.md §7.3):

    Within-app selection (Elixir) — mirror boundary structure in the test tree
    so `lib/billing` maps to `test/billing`, and derive selection from paths
    (Mix alias driven by git diff). Convention-checkable; no tag bookkeeping.

`boundary` hooks the compiler tracer and ExUnit files are runtime scripts, so
`boundary` cannot see the test tree (PLAN.md "Test selection"). The path
convention carries the within-app mapping instead, and this script is both
halves of it, so the two cannot drift apart:

  --check   The Moon task (`root:test`). Fails when a test file sits at a path
            that mirrors nothing under `lib/`.
  --select  The `mix test.changed` alias in each Elixir app's mix.exs. Prints
            the test paths mirroring the files that changed since a base ref.

Selection is a fast pre-merge gate, never the final word (seed.md §7.4): it is
a path heuristic, not a proof of coverage. Moon's own affected-detection and
the full suite on main are the backstop.

The mapping
-----------
For a changed source file `lib/<rel>.ex`:

  1. `test/<rel>_test.exs`, if that file exists.
  2. Otherwise the nearest existing ancestor directory of `test/<dirname(rel)>`
     that holds at least one `*_test.exs`, walking up towards `test/`.

Falling back to bare `test/` runs the whole suite: sound, just coarse.
`--check` lists those cases as information, not as failures — coarseness is
correct behaviour, an unmirrored *test* path is not.

Anything a changed file cannot be mapped from — `mix.exs`, `config/`, `priv/`,
`spec/`, test support files — selects the whole suite, since any of them can
change every test's outcome.

No third-party dependencies, so the sandbox image needs no Python packages.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent

# Mix tasks have no mirrored test directory by design, so --check does not
# report them as coarse. They still *select* the whole suite like anything
# else with no mirrored path — `core.bootstrap` creates the Postgres role and
# schema every test in the app runs against.
COARSE_REPORT_EXEMPT = ("mix/",)

WHOLE_SUITE = "test"


def elixir_apps() -> dict[str, Path]:
    """Direct subdirectories of the repo root holding a mix.exs — mirrors the
    `globs: ["*"]` project source pattern in .moon/workspace.yml."""
    return {
        p.name: p
        for p in sorted(REPO_ROOT.iterdir())
        if p.is_dir() and not p.name.startswith(".") and (p / "mix.exs").exists()
    }


def source_files(app_dir: Path) -> list[Path]:
    """Every `lib/**/*.ex`, as paths relative to the app directory."""
    lib = app_dir / "lib"
    if not lib.is_dir():
        return []
    return sorted(p.relative_to(app_dir) for p in lib.rglob("*.ex"))


def test_files(app_dir: Path) -> list[Path]:
    """Every `test/**/*_test.exs`, as paths relative to the app directory."""
    test = app_dir / "test"
    if not test.is_dir():
        return []
    return sorted(p.relative_to(app_dir) for p in test.rglob("*_test.exs"))


def has_tests(directory: Path) -> bool:
    return directory.is_dir() and any(directory.rglob("*_test.exs"))


def test_target(app_dir: Path, source: Path) -> str:
    """Map `lib/<rel>.ex` to the test path that covers it. See "The mapping"."""
    rel = source.relative_to("lib")

    mirrored_file = Path("test") / rel.with_name(rel.stem + "_test.exs")
    if (app_dir / mirrored_file).is_file():
        return str(mirrored_file)

    candidate = Path("test") / rel.parent
    while candidate != Path("test"):
        if has_tests(app_dir / candidate):
            return str(candidate)
        candidate = candidate.parent

    return WHOLE_SUITE


def mirrors_lib(app_dir: Path, test_file: Path) -> bool:
    """True when a test file's path mirrors something real under `lib/`: either
    the module it names (`test/a/b_test.exs` -> `lib/a/b.ex`) or the directory
    it sits in (`test/a/` -> `lib/a/`)."""
    rel = test_file.relative_to("test")

    mirrored_source = Path("lib") / rel.with_name(rel.name.removesuffix("_test.exs") + ".ex")
    if (app_dir / mirrored_source).is_file():
        return True

    return (app_dir / "lib" / rel.parent).is_dir()


def check() -> int:
    apps = elixir_apps()
    if not apps:
        print("test-paths: no mix.exs files found — nothing to check, passing trivially.")
        return 0

    violations = []

    for app, app_dir in apps.items():
        for test_file in test_files(app_dir):
            if not mirrors_lib(app_dir, test_file):
                violations.append((app, test_file))

        sources = source_files(app_dir)
        # A file directly under `lib/` names the app's root module; it has no
        # area to mirror, so `test/` is its correct target, not a fallback.
        coarse = [
            s
            for s in sources
            if s.parent != Path("lib")
            and not str(s.relative_to("lib")).startswith(COARSE_REPORT_EXEMPT)
            and test_target(app_dir, s) == WHOLE_SUITE
        ]
        if coarse:
            print(
                f"test-paths: {app} — {len(coarse)} of {len(sources)} lib/ file(s) have no "
                f"mirrored test path and select the whole suite."
            )

    for app, test_file in violations:
        print(f"test-paths: VIOLATION in {app}")
        print(f"  {test_file} mirrors neither a lib/ module nor a lib/ directory.")

    if violations:
        print(
            "test-paths: FAILED — the test tree no longer mirrors lib/ (see above). "
            "Move the test file, or add the lib/ path it claims to cover."
        )
        return 1

    print(f"test-paths: OK — {len(apps)} Elixir app(s) checked, every test path mirrors lib/.")
    return 0


def changed_files(base: str) -> list[str]:
    """Paths changed against `base`, relative to the repo root, including
    uncommitted and untracked work."""
    diff = subprocess.run(
        ["git", "diff", "--name-only", base],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return (diff.stdout + untracked.stdout).split()


def select(app: str, base: str) -> int:
    app_dir = REPO_ROOT / app
    targets: set[str] = set()

    for changed in changed_files(base):
        path = Path(changed)
        if not path.is_relative_to(app):
            continue

        rel = path.relative_to(app)

        if rel.parts[0] == "lib" and rel.suffix == ".ex":
            # No exemptions here: a `lib/mix/**` task has no mirrored test
            # path, so the walk-up lands on the whole suite, which is right.
            targets.add(test_target(app_dir, rel))
        elif rel.parts[0] == "test" and rel.name.endswith("_test.exs"):
            targets.add(str(rel))
        else:
            # mix.exs, config/, priv/, spec/, test support: no mirrored path,
            # and any of them can change every test's outcome.
            targets.add(WHOLE_SUITE)

    if WHOLE_SUITE in targets:
        targets = {WHOLE_SUITE}

    # Drop file targets already covered by a selected directory.
    directories = {t for t in targets if not t.endswith(".exs")}
    targets = {
        t
        for t in targets
        if t in directories or not any(Path(t).is_relative_to(d) for d in directories)
    }

    for target in sorted(targets):
        print(target)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="check the convention holds")
    mode.add_argument("--select", action="store_true", help="print the test paths to run")
    parser.add_argument("--app", help="Elixir app directory name (with --select)")
    parser.add_argument("--base", default="main", help="git ref to diff against (default: main)")
    args = parser.parse_args()

    if args.check:
        return check()

    if not args.app:
        parser.error("--select requires --app")
    return select(args.app, args.base)


if __name__ == "__main__":
    sys.exit(main())

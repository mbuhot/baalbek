"""Records which source the committed WASM artifact was built from, and checks it.

`check` fails unless the recording exists and matches both the current source
and the committed artifact. `accept` rewrites the recording, and the artifact
when its bytes moved.
"""

import hashlib
import pathlib
import subprocess
import sys

ARTIFACT = pathlib.Path("plugin/moon_elixir_plugin.wasm")
FRESH = pathlib.Path("plugin/moon_elixir_plugin.wasm.new")
RECORD = pathlib.Path("plugin/moon_elixir_plugin.provenance")

# Every path the fingerprint walks, and it must stay equal to the build task's
# own `inputs` in ../moon.yml, which says so too. A declared input left out of
# this list lets a stale artifact pass, so the two move together. Reading the
# list from moon instead was tried and reverted; adr-0002 records why.
SOURCE_PATHS = ["Cargo.toml", "Cargo.lock", "src", "scripts"]

SECTIONS = {0: "custom", 1: "type", 2: "import", 3: "function", 4: "table",
            5: "memory", 6: "global", 7: "export", 8: "start", 9: "element",
            10: "code", 11: "data", 12: "data count", 13: "tag"}


def fail(*lines):
    for line in lines:
        print(line, file=sys.stderr)
    sys.exit(1)


def source_digest():
    """One digest over the name and content of every fingerprinted file."""
    files = []
    for path in map(pathlib.Path, SOURCE_PATHS):
        if path.is_dir():
            files.extend(child for child in path.rglob("*") if child.is_file())
        elif path.is_file():
            files.append(path)
        else:
            fail(f"moon-elixir-plugin: {path} is declared as an input but is missing.")
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(str(path).encode())
        digest.update(b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def read_record():
    """The recorded digests, or a failure if the recording cannot be trusted."""
    if not RECORD.exists():
        fail(f"moon-elixir-plugin: {RECORD} is missing, so the committed",
             f"{ARTIFACT} has no recorded provenance.",
             "Rebuild and record it with: bash scripts/build.sh --accept")
    recorded = {}
    for line in RECORD.read_text().splitlines():
        fields = line.split()
        if len(fields) == 2:
            recorded[fields[0]] = fields[1]
    missing = {"source", "artifact"} - recorded.keys()
    bad = [key for key, value in recorded.items() if len(value) != 64]
    if missing or bad:
        fail(f"moon-elixir-plugin: {RECORD} is not readable as provenance",
             f"(missing {sorted(missing)}, malformed {sorted(bad)}).",
             "Rebuild and record it with: bash scripts/build.sh --accept")
    return recorded


def write_record(source, artifact):
    RECORD.write_text(f"source {source}\nartifact {artifact}\n")


def leb128(data, at):
    """Reads one unsigned LEB128 integer, and returns it with the next offset."""
    value = shift = 0
    while True:
        byte = data[at]
        at += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, at
        shift += 7


def locate(data, offset):
    """Names the wasm section a byte offset falls in."""
    at = 8
    while at < len(data) and at <= offset:
        name = SECTIONS.get(data[at], f"id {data[at]}")
        size, body = leb128(data, at + 1)
        if offset == at:
            return f'the "{name}" section id'
        if offset < body:
            return f'the "{name}" section\'s declared length'
        if offset < body + size:
            return f'inside the "{name}" section, {offset - body} bytes into {size}'
        at = body + size
    return "past every section this file declares"


def compare_bytes(old, new):
    """Where two artifacts diverge, and which toolchain built the fresh one."""
    rustc = subprocess.run(["rustc", "-vV"], capture_output=True, text=True).stdout
    reported = [field for field in rustc.splitlines()
                if field.startswith(("release:", "host:"))]
    lines = [f"  rustc {field}" for field in reported]
    lines.append(f"  committed: {len(old)} bytes, freshly built: {len(new)} bytes")
    shared = min(len(old), len(new))
    first = next((i for i in range(shared) if old[i] != new[i]), shared)
    lines.append(f"  first difference at byte {first}: {locate(old, first)}")
    return lines


def main():
    mode = sys.argv[1]
    source = source_digest()
    fresh = FRESH.read_bytes()

    if mode == "accept":
        if ARTIFACT.read_bytes() != fresh:
            ARTIFACT.write_bytes(fresh)
            print(f"moon-elixir-plugin: replaced {ARTIFACT} with the fresh build.")
        write_record(source, hashlib.sha256(ARTIFACT.read_bytes()).hexdigest())
        print(f"moon-elixir-plugin: recorded {RECORD}. Commit it with the artifact.")
        return

    recorded = read_record()
    committed = ARTIFACT.read_bytes()
    artifact = hashlib.sha256(committed).hexdigest()
    divergence = compare_bytes(committed, fresh) if committed != fresh else []

    if recorded["artifact"] != artifact:
        fail(f"moon-elixir-plugin: {ARTIFACT} is not the artifact {RECORD} records.",
             f"  recorded: {recorded['artifact']}", f"  on disk:  {artifact}",
             "Either restore it, or rebuild and record it with:",
             "  bash scripts/build.sh --accept")

    if recorded["source"] != source:
        fail(f"moon-elixir-plugin: the committed {ARTIFACT} was not built from",
             "this source.", f"  recorded source: {recorded['source']}",
             f"  this source:     {source}", *divergence,
             "Rebuild and record it with: bash scripts/build.sh --accept")

    # Reached only when the source matches: the bytes are then allowed to
    # differ, because the same rustc emits different wasm from an x86_64 host
    # than from an aarch64 one (adr-0002).
    for line in divergence:
        print(f"note:{line}", file=sys.stderr)
    print(f"moon-elixir-plugin: {ARTIFACT} was built from this source.")


main()

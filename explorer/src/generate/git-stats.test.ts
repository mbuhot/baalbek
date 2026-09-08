import { describe, expect, it } from "vitest";
import {
  coChangeBreadthLimit,
  distinctCommits,
  markUndeclared,
  ownerOf,
  parseGitLog,
  summarise,
} from "./git-stats.ts";

const COUPLE = new Set(["core", "core-api-client", "web"]);

const SOURCES = new Map([
  ["root", "."],
  ["core", "core"],
  ["core-api-client", "core-api-client"],
  ["web", "web"],
]);

function log(entries: [string, string, string[]][]): string {
  return entries.map(([hash, date, files]) => `\x1e${hash}\x1f${date}\n${files.join("\n")}\n`).join("");
}

describe("parseGitLog", () => {
  it("reads hash, date, and touched files per commit", () => {
    const commits = parseGitLog(log([["abc", "2026-09-01T00:00:00+00:00", ["core/lib/a.ex", "web/src/b.ts"]]]));
    expect(commits).toEqual([
      { hash: "abc", date: "2026-09-01T00:00:00+00:00", files: ["core/lib/a.ex", "web/src/b.ts"] },
    ]);
  });

  it("keeps a commit that touched no files", () => {
    expect(parseGitLog(log([["abc", "2026-09-01T00:00:00+00:00", []]]))).toHaveLength(1);
  });
});

describe("ownerOf", () => {
  it("prefers the longest matching project source", () => {
    expect(ownerOf("core-api-client/src/index.ts", SOURCES)).toBe("core-api-client");
  });

  it("does not let a source prefix match a sibling directory", () => {
    expect(ownerOf("core/lib/a.ex", SOURCES)).toBe("core");
  });

  it("falls back to the root pseudo-project for a top-level file", () => {
    expect(ownerOf("README.md", SOURCES)).toBe("root");
  });
});

describe("summarise", () => {
  const commits = parseGitLog(
    log([
      ["c1", "2026-09-02T00:00:00+00:00", ["core/lib/a.ex", "core/lib/b.ex", "web/src/x.ts"]],
      ["c2", "2026-09-01T00:00:00+00:00", ["core/lib/a.ex"]],
    ]),
  );

  it("counts commits and file changes per project", () => {
    const { change } = summarise(commits, SOURCES, COUPLE);
    expect(change.get("core")).toEqual({ commits: 2, files: 3, lastChanged: "2026-09-02T00:00:00+00:00" });
    expect(change.get("web")?.commits).toBe(1);
  });

  it("reports a project with no history rather than omitting it", () => {
    expect(summarise(commits, SOURCES, COUPLE).change.get("core-api-client")).toEqual({
      commits: 0,
      files: 0,
      lastChanged: null,
    });
  });

  it("counts a co-change pair once per commit, not once per file", () => {
    const { coupling } = summarise(commits, SOURCES, COUPLE);
    expect(coupling).toEqual([{ a: "core", b: "web", commits: 1, undeclared: false }]);
  });

  it("does not pair a commit that touched more than a third of the components", () => {
    const wide = parseGitLog(
      log([["c4", "2026-09-04T00:00:00+00:00", ["core/lib/a.ex", "web/src/x.ts", "core-api-client/src/i.ts"]]]),
    );
    const { change, coupling } = summarise(wide, SOURCES, COUPLE);
    expect(coupling).toEqual([]);
    // The commit still counts towards change frequency; only the pairing is dropped.
    expect(change.get("core")?.commits).toBe(1);
  });

  it("never lets the breadth limit fall below a pair", () => {
    expect(coChangeBreadthLimit(1)).toBe(2);
    expect(coChangeBreadthLimit(12)).toBe(4);
  });

  it("keeps the root pseudo-project out of co-change, since its source owns every top-level file", () => {
    const withRoot = parseGitLog(log([["c3", "2026-09-03T00:00:00+00:00", ["README.md", "core/lib/a.ex"]]]));
    expect(summarise(withRoot, SOURCES, COUPLE).coupling).toEqual([]);
    expect(summarise(withRoot, SOURCES, COUPLE).change.get("root")?.commits).toBe(1);
  });
});

describe("distinctCommits", () => {
  const commits = parseGitLog(
    log([
      ["c1", "2026-09-02T00:00:00+00:00", ["core/lib/a.ex", "web/src/x.ts"]],
      ["c2", "2026-09-01T00:00:00+00:00", ["core/lib/a.ex"]],
    ]),
  );

  it("counts a commit touching two of the components once", () => {
    expect(distinctCommits(commits, SOURCES, ["core", "web"])).toBe(2);
  });

  it("counts only the commits that touched the named components", () => {
    expect(distinctCommits(commits, SOURCES, ["web"])).toBe(1);
  });
});

describe("markUndeclared", () => {
  const coupling = [
    { a: "core", b: "web", commits: 3, undeclared: false },
    { a: "core", b: "root", commits: 2, undeclared: false },
  ];

  it("clears the flag when an edge exists in either direction", () => {
    const marked = markUndeclared(coupling, [{ from: "web", to: "core" }]);
    expect(marked[0]?.undeclared).toBe(false);
  });

  it("clears the flag when the edge is only reachable transitively", () => {
    const marked = markUndeclared(coupling, [
      { from: "web", to: "core-api-client" },
      { from: "core-api-client", to: "core" },
    ]);
    expect(marked[0]?.undeclared).toBe(false);
  });

  it("flags a pair no declared edge explains", () => {
    expect(markUndeclared(coupling, [])[1]?.undeclared).toBe(true);
  });
});

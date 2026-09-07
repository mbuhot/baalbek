import { describe, expect, it } from "vitest";
import { parsePlaywrightList, specsByCapability, validateSpecClaims } from "./e2e-specs.ts";

// The shape `playwright test --list --reporter=json` emits. Its `tags` have the leading `@` stripped.
const LIST = {
  suites: [
    {
      file: "dispatch-board.spec.ts",
      specs: [
        { title: "shows a job", file: "dispatch-board.spec.ts", tags: ["capability/dispatch-board"] },
      ],
      suites: [
        {
          file: "dispatch-board.spec.ts",
          specs: [{ title: "nested", file: "dispatch-board.spec.ts", tags: ["capability/job-intake", "slow"] }],
        },
      ],
    },
  ],
};

describe("parsePlaywrightList", () => {
  it("reads the capability tags out of every spec, including nested describes", () => {
    expect(parsePlaywrightList(LIST)).toEqual([
      {
        id: "dispatch-board.spec.ts › nested",
        file: "dispatch-board.spec.ts",
        title: "nested",
        capabilities: ["job-intake"],
      },
      {
        id: "dispatch-board.spec.ts › shows a job",
        file: "dispatch-board.spec.ts",
        title: "shows a job",
        capabilities: ["dispatch-board"],
      },
    ]);
  });

  it("accepts the tag with or without the leading @, so a reporter change cannot go silently unnoticed", () => {
    const specs = parsePlaywrightList({
      suites: [{ file: "a.spec.ts", specs: [{ title: "t", file: "a.spec.ts", tags: ["@capability/invoicing"] }] }],
    });
    expect(specs[0]?.capabilities).toEqual(["invoicing"]);
  });
});

describe("validateSpecClaims", () => {
  const defined = new Set(["dispatch-board", "job-intake"]);

  it("passes a suite whose every spec claims a defined capability", () => {
    expect(validateSpecClaims(parsePlaywrightList(LIST), defined)).toEqual([]);
  });

  it("fails a spec tagged with a capability the vocabulary does not define", () => {
    const specs = parsePlaywrightList({
      suites: [{ file: "a.spec.ts", specs: [{ title: "t", file: "a.spec.ts", tags: ["capability/typo"] }] }],
    });
    expect(validateSpecClaims(specs, defined)).toEqual([
      'e2e spec "a.spec.ts › t" is tagged @capability/typo, which capabilities.yml does not define',
    ]);
  });

  it("fails a spec that claims nothing", () => {
    const specs = parsePlaywrightList({
      suites: [{ file: "a.spec.ts", specs: [{ title: "t", file: "a.spec.ts", tags: [] }] }],
    });
    expect(validateSpecClaims(specs, defined)[0]).toContain("claims no capability");
  });
});

describe("specsByCapability", () => {
  it("reports an uncovered capability as an empty list rather than omitting it", () => {
    const byCapability = specsByCapability(parsePlaywrightList(LIST), new Set(["dispatch-board", "invoicing"]));
    expect(byCapability.get("dispatch-board")).toEqual(["dispatch-board.spec.ts › shows a job"]);
    expect(byCapability.get("invoicing")).toEqual([]);
  });
});

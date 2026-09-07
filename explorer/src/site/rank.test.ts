import { describe, expect, it } from "vitest";
import type { Capability, ExplorerModel } from "../model.ts";
import { externalCoupling, heatBucket, rankCapabilities } from "./rank.ts";

function capability(id: string, components: string[], commits: number): Capability {
  return { id, name: id, description: "x", components, commits, sharedComponents: [], specs: [] };
}

describe("heatBucket", () => {
  it("puts nothing in a bucket when there is no history", () => {
    expect(heatBucket(0, 10)).toBe(0);
    expect(heatBucket(5, 0)).toBe(0);
  });

  it("puts the busiest value in the top bucket", () => {
    expect(heatBucket(10, 10)).toBe(4);
  });

  it("never drops a non-zero value into the empty bucket", () => {
    expect(heatBucket(1, 100)).toBe(1);
  });
});

describe("externalCoupling", () => {
  it("counts only pairs that cross the capability boundary", () => {
    const coupling = [
      { a: "core", b: "server", commits: 5, undeclared: false },
      { a: "core", b: "web", commits: 2, undeclared: true },
    ];
    expect(externalCoupling(capability("c", ["core", "server"], 0), coupling)).toBe(2);
  });
});

describe("rankCapabilities", () => {
  const model = {
    capabilities: [capability("low", ["a"], 1), capability("high", ["b"], 9)],
    coupling: [{ a: "a", b: "z", commits: 7, undeclared: false }],
  } as ExplorerModel;

  it("orders by change when the change overlay is selected", () => {
    expect(rankCapabilities(model, "change").map((r) => r.capability.id)).toEqual(["high", "low"]);
  });

  it("orders by cross-capability coupling when that overlay is selected", () => {
    expect(rankCapabilities(model, "coupling").map((r) => r.capability.id)).toEqual(["low", "high"]);
  });
});

/** Invariants over the real generated model, which no fixture can satisfy by accident. */

import { describe, expect, it } from "vitest";
import type { ExplorerModel } from "./model.ts";
import raw from "./generated/model.json";

const model = raw as unknown as ExplorerModel;
const ids = new Set(model.projects.map((project) => project.id));

describe("src/generated/model.json", () => {
  it("came from this workspace, not a fixture", () => {
    expect(model.projects.length).toBeGreaterThanOrEqual(10);
    expect(model.commit).toMatch(/^[0-9a-f]{40}$/);
    for (const id of ["core", "server", "web", "timeline", "pricing", "explorer"]) expect(ids.has(id)).toBe(true);
  });

  it("names a real project at both ends of every declared edge", () => {
    for (const edge of model.projectEdges) {
      expect(ids.has(edge.from)).toBe(true);
      expect(ids.has(edge.to)).toBe(true);
    }
  });

  it("names a real task at both ends of every task edge", () => {
    const targets = new Set(model.projects.flatMap((project) => project.tasks.map((task) => task.target)));
    for (const edge of model.taskEdges) {
      expect(targets.has(edge.from)).toBe(true);
      expect(targets.has(edge.to)).toBe(true);
    }
  });

  it("claims every project exactly once, by a capability or by the platform list", () => {
    for (const project of model.projects) {
      expect(project.capabilities.length > 0 || project.platformReason !== null).toBe(true);
      expect(project.capabilities.length > 0 && project.platformReason !== null).toBe(false);
    }
  });

  it("resolves every capability component to a project in the graph", () => {
    for (const capability of model.capabilities) {
      expect(capability.components.length).toBeGreaterThan(0);
      for (const component of capability.components) expect(ids.has(component)).toBe(true);
    }
  });

  it("agrees both ways about which project serves which capability", () => {
    for (const capability of model.capabilities) {
      for (const component of capability.components) {
        expect(model.projects.find((project) => project.id === component)?.capabilities).toContain(capability.id);
      }
    }
    for (const project of model.projects) {
      for (const id of project.capabilities) {
        expect(model.capabilities.find((capability) => capability.id === id)?.components).toContain(project.id);
      }
    }
  });

  it("reads e2e coverage from the suite, and reports the gap rather than failing on it", () => {
    const covered = model.capabilities.filter((capability) => capability.specs.length > 0);
    expect(covered.length).toBeGreaterThan(0);
    const uncovered = model.capabilities.filter((capability) => capability.specs.length === 0).map((c) => c.id);
    expect(model.gaps.find((gap) => gap.id === "capabilities-without-e2e")?.items).toEqual(uncovered);
  });

  it("builds the explorer itself, so the site is in the graph it draws", () => {
    const explorer = model.projects.find((project) => project.id === "explorer");
    expect(explorer?.tasks.map((task) => task.id)).toContain("build");
  });

  it("keeps every derived blind spot populated or explicitly empty", () => {
    expect(model.gaps.length).toBeGreaterThan(0);
    for (const gap of model.gaps) {
      expect(gap.explanation.length).toBeGreaterThan(40);
      expect(Array.isArray(gap.items)).toBe(true);
    }
  });

  it("still records the e2e edges adr-0006 says carry no hashable dependency", () => {
    const e2eEdges = model.projectEdges.filter((edge) => edge.from === "e2e");
    expect(e2eEdges.length).toBeGreaterThan(0);
    for (const edge of e2eEdges) expect(edge.strength).toBe("declared-only");
  });
});

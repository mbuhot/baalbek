import { describe, expect, it } from "vitest";
import type { Capability, CouplingPair, ProjectEdge, ProjectNode, TaskEdge } from "../model.ts";
import { deriveGaps } from "./gaps.ts";

function project(id: string, overrides: Partial<ProjectNode> = {}): ProjectNode {
  return {
    id,
    source: id,
    language: "typescript",
    layer: "library",
    toolchains: [],
    tasks: [],
    change: { commits: 0, files: 0, lastChanged: null },
    spec: { features: [], decisions: [], mocks: [] },
    capabilities: [],
    platformReason: null,
    hasConfigFile: true,
    ...overrides,
  };
}

function task(target: string, cache: boolean): ProjectNode["tasks"][number] {
  return { id: target.split(":")[1] ?? "", target, description: null, outputs: [], cache, runInCI: true };
}

function edge(from: string, to: string, strength: ProjectEdge["strength"]): ProjectEdge {
  return { from, to, scope: "production", strength, hashingTaskDeps: [], ignoredTaskDeps: [] };
}

function gapById(gaps: ReturnType<typeof deriveGaps>, id: string): string[] {
  return gaps.find((gap) => gap.id === id)?.items ?? [];
}

const base = {
  projects: [] as ProjectNode[],
  projectEdges: [] as ProjectEdge[],
  taskEdges: [] as TaskEdge[],
  capabilities: [] as Capability[],
  coupling: [] as CouplingPair[],
};

describe("deriveGaps", () => {
  it("lists declared edges that cannot invalidate a cache", () => {
    const gaps = deriveGaps({
      ...base,
      projectEdges: [edge("e2e", "web", "declared-only"), edge("web", "core", "direct")],
    });
    expect(gapById(gaps, "declaration-only-edges")).toEqual(["e2e -> web"]);
  });

  it("lists task deps moon records as ignored", () => {
    const gaps = deriveGaps({
      ...base,
      taskEdges: [
        { from: "a:test", to: "b:image", hashing: false },
        { from: "a:test", to: "b:build", hashing: true },
      ],
    });
    expect(gapById(gaps, "ignored-task-deps")).toEqual(["a:test -> b:image"]);
  });

  it("lists uncached tasks and projects with no tasks", () => {
    const gaps = deriveGaps({
      ...base,
      projects: [project("a", { tasks: [task("a:image", false), task("a:build", true)] }), project("b")],
    });
    expect(gapById(gaps, "uncached-tasks")).toEqual(["a:image"]);
    expect(gapById(gaps, "taskless-projects")).toEqual(["b"]);
  });

  it("reports only co-change that no declared edge explains, and only when repeated", () => {
    const gaps = deriveGaps({
      ...base,
      coupling: [
        { a: "core", b: "billing", commits: 4, undeclared: true },
        { a: "core", b: "web", commits: 9, undeclared: false },
        { a: "core", b: "identity", commits: 1, undeclared: true },
      ],
    });
    expect(gapById(gaps, "undeclared-co-change")).toEqual(["core + billing (4 commits)"]);
  });

  it("lists a project moon discovered from a directory rather than from a moon.yml", () => {
    const gaps = deriveGaps({
      ...base,
      projects: [project("config", { hasConfigFile: false }), project("core")],
    });
    expect(gapById(gaps, "glob-discovered-projects")).toEqual(["config"]);
  });

  it("reports a capability no e2e spec claims, rather than failing on it", () => {
    const capability = (id: string, specs: string[]): Capability => ({
      id,
      name: id,
      description: "x",
      components: [],
      commits: 0,
      sharedComponents: [],
      specs,
    });
    const gaps = deriveGaps({
      ...base,
      capabilities: [capability("invoicing", []), capability("dispatch-board", ["a.spec.ts › t"])],
    });
    expect(gapById(gaps, "capabilities-without-e2e")).toEqual(["invoicing"]);
  });

  it("reports a capability whose components no build edge connects", () => {
    const capability = (components: string[]): Capability => ({
      id: "c",
      name: "C",
      description: "x",
      components,
      commits: 0,
      sharedComponents: [],
      specs: [],
    });
    const split = deriveGaps({ ...base, capabilities: [capability(["a", "b"])] });
    expect(gapById(split, "split-capabilities")).toEqual(["c: a | b"]);

    const joined = deriveGaps({
      ...base,
      capabilities: [capability(["a", "b"])],
      projectEdges: [edge("a", "b", "direct")],
    });
    expect(gapById(joined, "split-capabilities")).toEqual([]);
  });
});

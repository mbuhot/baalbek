import { describe, expect, it } from "vitest";
import { classifyProjectEdges, readMoonGraph, type RawGraph, type RawProject, type RawTask } from "./moon-graph.ts";

function projectGraph(
  ids: string[],
  edges: [number, number][],
): RawGraph<RawProject> {
  return {
    graph: { nodes: ids.map((_, i) => i), edges: edges.map(([a, b]) => [a, b, "production"]) },
    data: Object.fromEntries(
      ids.map((id, i) => [String(i), { id, source: id, language: "elixir", layer: "library", toolchains: [] }]),
    ),
  };
}

function taskGraph(
  tasks: { target: string; outputs?: string[] }[],
  edges: [number, number][],
): RawGraph<RawTask> {
  return {
    graph: { nodes: tasks.map((_, i) => i), edges: edges.map(([a, b]) => [a, b, "required"]) },
    data: Object.fromEntries(
      tasks.map((task, i) => [
        String(i),
        {
          id: task.target.split(":")[1] ?? "",
          target: task.target,
          outputs: (task.outputs ?? []).map((file) => ({ file })),
          options: { cache: true, runInCI: true },
        },
      ]),
    ),
  };
}

describe("readMoonGraph", () => {
  it("resolves petgraph node indices back to ids", () => {
    const graph = readMoonGraph(projectGraph(["a", "b"], [[0, 1]]), taskGraph([], []));
    expect(graph.projectEdges).toEqual([{ from: "a", to: "b", scope: "production" }]);
  });

  it("groups tasks under their project and records declared outputs", () => {
    const graph = readMoonGraph(
      projectGraph(["a"], []),
      taskGraph([{ target: "a:build", outputs: ["build/x"] }, { target: "a:test" }], []),
    );
    expect(graph.tasksByProject.get("a")?.map((t) => [t.id, t.outputs])).toEqual([
      ["build", ["build/x"]],
      ["test", []],
    ]);
  });

  it("marks a task dep on an output-less task as non-hashing", () => {
    const graph = readMoonGraph(
      projectGraph(["a"], []),
      taskGraph([{ target: "a:test" }, { target: "a:bootstrap" }], [[0, 1]]),
    );
    expect(graph.taskEdges).toEqual([{ from: "a:test", to: "a:bootstrap", hashing: false }]);
  });
});

describe("classifyProjectEdges", () => {
  it("calls an edge direct when a task dep lands on an output-declaring task", () => {
    const graph = readMoonGraph(
      projectGraph(["a", "b"], [[0, 1]]),
      taskGraph([{ target: "a:build" }, { target: "b:build", outputs: ["build/b"] }], [[0, 1]]),
    );
    const [edge] = classifyProjectEdges(graph);
    expect(edge?.strength).toBe("direct");
    expect(edge?.hashingTaskDeps).toEqual(["a:build -> b:build"]);
  });

  it("calls an edge declared-only when the upstream task declares no outputs", () => {
    const graph = readMoonGraph(
      projectGraph(["a", "b"], [[0, 1]]),
      taskGraph([{ target: "a:test" }, { target: "b:image" }], [[0, 1]]),
    );
    const [edge] = classifyProjectEdges(graph);
    expect(edge?.strength).toBe("declared-only");
    expect(edge?.ignoredTaskDeps).toEqual(["a:test -> b:image"]);
  });

  it("calls an edge transitive when the hash reaches it only through a third project", () => {
    // a -> b -> c declared; a's tasks only depend on b's, and b's on c's.
    const graph = readMoonGraph(
      projectGraph(["a", "b", "c"], [
        [0, 1],
        [1, 2],
        [0, 2],
      ]),
      taskGraph(
        [
          { target: "a:build", outputs: ["build/a"] },
          { target: "b:build", outputs: ["build/b"] },
          { target: "c:build", outputs: ["build/c"] },
        ],
        [
          [0, 1],
          [1, 2],
        ],
      ),
    );
    const strengths = Object.fromEntries(classifyProjectEdges(graph).map((e) => [`${e.from}->${e.to}`, e.strength]));
    expect(strengths).toEqual({ "a->b": "direct", "a->c": "transitive", "b->c": "direct" });
  });

  it("does not treat a non-hashing hop as a transitive path", () => {
    const graph = readMoonGraph(
      projectGraph(["a", "b", "c"], [[0, 2]]),
      taskGraph(
        [{ target: "a:build" }, { target: "b:image" }, { target: "c:build", outputs: ["build/c"] }],
        [
          [0, 1],
          [1, 2],
        ],
      ),
    );
    expect(classifyProjectEdges(graph)[0]?.strength).toBe("declared-only");
  });
});

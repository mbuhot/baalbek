/** Turns `moon project-graph --json` and `moon task-graph --json` into the explorer's node and edge lists. */

import type { EdgeStrength, ProjectEdge, ProjectTask, TaskEdge } from "../model.ts";

/** A petgraph serialisation: `nodes` are indices into `data`, `edges` are `[from, to, scope]`. */
export interface RawGraph<T> {
  graph: {
    nodes: number[];
    edges: [number, number, string][];
  };
  data: Record<string, T>;
}

export interface RawProject {
  id: string;
  source: string;
  language: string;
  layer: string;
  toolchains?: string[];
  /** The project's own `moon.yml`, as moon resolved it. `tags` is where a capability claim lives. */
  config?: { tags?: string[] };
}

export interface RawTask {
  id: string;
  target: string;
  description?: string | null;
  outputs?: { file?: string; glob?: string }[];
  options?: { cache?: boolean; runInCI?: boolean };
}

export interface MoonGraph {
  projects: RawProject[];
  projectEdges: { from: string; to: string; scope: string }[];
  tasksByProject: Map<string, ProjectTask[]>;
  taskEdges: TaskEdge[];
}

function outputPaths(task: RawTask): string[] {
  return (task.outputs ?? []).map((o) => o.file ?? o.glob ?? "");
}

function projectOf(target: string): string {
  return target.split(":")[0] ?? target;
}

function resolveEdges<T>(raw: RawGraph<T>, key: (item: T) => string): { from: string; to: string; scope: string }[] {
  const byIndex = new Map<number, string>();
  for (const [index, item] of Object.entries(raw.data)) byIndex.set(Number(index), key(item));
  const edges: { from: string; to: string; scope: string }[] = [];
  for (const [from, to, scope] of raw.graph.edges) {
    const a = byIndex.get(from);
    const b = byIndex.get(to);
    if (a !== undefined && b !== undefined) edges.push({ from: a, to: b, scope });
  }
  return edges;
}

export function readMoonGraph(projectGraph: RawGraph<RawProject>, taskGraph: RawGraph<RawTask>): MoonGraph {
  const projects = Object.values(projectGraph.data).sort((a, b) => a.id.localeCompare(b.id));
  const projectEdges = resolveEdges(projectGraph, (p) => p.id);

  const tasksByProject = new Map<string, ProjectTask[]>();
  for (const project of projects) tasksByProject.set(project.id, []);
  for (const task of Object.values(taskGraph.data)) {
    const list = tasksByProject.get(projectOf(task.target));
    if (list === undefined) continue;
    list.push({
      id: task.id,
      target: task.target,
      description: task.description ?? null,
      outputs: outputPaths(task),
      cache: task.options?.cache ?? true,
      runInCI: task.options?.runInCI ?? true,
    });
  }
  for (const list of tasksByProject.values()) list.sort((a, b) => a.id.localeCompare(b.id));

  const declaresOutputs = new Map<string, boolean>();
  for (const task of Object.values(taskGraph.data)) declaresOutputs.set(task.target, outputPaths(task).length > 0);

  const taskEdges: TaskEdge[] = resolveEdges(taskGraph, (t) => t.target)
    .map((edge) => ({ from: edge.from, to: edge.to, hashing: declaresOutputs.get(edge.to) === true }))
    .sort((a, b) => `${a.from}${a.to}`.localeCompare(`${b.from}${b.to}`));

  return { projects, projectEdges, tasksByProject, taskEdges };
}

// A hop only counts when the upstream task declares outputs, because Moon folds
// the upstream task's hash in only then (spec/decisions/adr-0006-*).
function hashingReach(taskEdges: TaskEdge[], from: string): Set<string> {
  const forward = new Map<string, string[]>();
  for (const edge of taskEdges) {
    if (!edge.hashing) continue;
    const list = forward.get(edge.from) ?? [];
    list.push(edge.to);
    forward.set(edge.from, list);
  }
  const seen = new Set<string>();
  const queue = [from];
  while (queue.length > 0) {
    const current = queue.pop() as string;
    for (const next of forward.get(current) ?? []) {
      if (seen.has(next)) continue;
      seen.add(next);
      queue.push(next);
    }
  }
  return seen;
}

/**
 * Grades every declared project edge by how it reaches Moon's hashing.
 *
 * `direct` has a task dep straight onto an output-declaring task of the
 * dependency. `transitive` reaches it only through other projects.
 * `declared-only` never reaches it, so the edge orders work and drives
 * affected-detection but cannot invalidate a cache.
 */
export function classifyProjectEdges(graph: MoonGraph): ProjectEdge[] {
  const reachCache = new Map<string, Set<string>>();
  const reachOf = (target: string): Set<string> => {
    let reach = reachCache.get(target);
    if (reach === undefined) {
      reach = hashingReach(graph.taskEdges, target);
      reachCache.set(target, reach);
    }
    return reach;
  };

  return graph.projectEdges
    .map(({ from, to, scope }) => {
      const fromTargets = (graph.tasksByProject.get(from) ?? []).map((t) => t.target);
      const hashingTaskDeps: string[] = [];
      const ignoredTaskDeps: string[] = [];
      for (const edge of graph.taskEdges) {
        if (edge.from.split(":")[0] !== from || edge.to.split(":")[0] !== to) continue;
        (edge.hashing ? hashingTaskDeps : ignoredTaskDeps).push(`${edge.from} -> ${edge.to}`);
      }
      let strength: EdgeStrength = "declared-only";
      if (hashingTaskDeps.length > 0) {
        strength = "direct";
      } else if (fromTargets.some((target) => [...reachOf(target)].some((r) => r.split(":")[0] === to))) {
        strength = "transitive";
      }
      return { from, to, scope, strength, hashingTaskDeps, ignoredTaskDeps };
    })
    .sort((a, b) => `${a.from}${a.to}`.localeCompare(`${b.from}${b.to}`));
}

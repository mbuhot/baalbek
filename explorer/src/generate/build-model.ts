/** Assembles the `ExplorerModel` from the four inputs seed.md §9 and PLAN.md name. */

import type { Capability, ExplorerModel, ProjectNode, ProjectSpec } from "../model.ts";
import type { CapabilityFile, ResolvedClaims } from "./capabilities.ts";
import { distinctCommits, markUndeclared, summarise, type Commit } from "./git-stats.ts";
import { deriveGaps } from "./gaps.ts";
import { classifyProjectEdges, readMoonGraph, type RawGraph, type RawProject, type RawTask } from "./moon-graph.ts";

export interface BuildInputs {
  projectGraph: RawGraph<RawProject>;
  taskGraph: RawGraph<RawTask>;
  capabilityFile: CapabilityFile;
  claims: ResolvedClaims;
  /** Capability id -> the e2e specs tagged with it. */
  specsByCapability: Map<string, string[]>;
  commits: Commit[];
  historyLimit: number;
  /** Every tracked file, as `git ls-files` reports it. */
  trackedFiles: string[];
  /** Repository-relative path of every `moon.yml` that exists, so glob-discovered projects stand out. */
  configFiles: string[];
  generatedAt: string;
  commit: string;
}

function specOf(source: string, trackedFiles: string[]): ProjectSpec {
  const prefix = source === "." ? "spec/" : `${source}/spec/`;
  const pick = (kind: string): string[] =>
    trackedFiles.filter((file) => file.startsWith(`${prefix}${kind}/`)).sort();
  return { features: pick("features"), decisions: pick("decisions"), mocks: pick("mocks") };
}

export function buildModel(inputs: BuildInputs): ExplorerModel {
  const graph = readMoonGraph(inputs.projectGraph, inputs.taskGraph);
  const projectEdges = classifyProjectEdges(graph);

  const sources = new Map(graph.projects.map((project) => [project.id, project.source]));
  const configFiles = new Set(inputs.configFiles);

  const { capabilitiesOf, componentsOf, platformReasons } = inputs.claims;
  const stats = summarise(inputs.commits, sources, new Set([...componentsOf.values()].flat()));

  const projects: ProjectNode[] = graph.projects.map((project) => ({
    id: project.id,
    source: project.source,
    language: project.language,
    layer: project.layer,
    toolchains: project.toolchains ?? [],
    tasks: graph.tasksByProject.get(project.id) ?? [],
    change: stats.change.get(project.id) ?? { commits: 0, files: 0, lastChanged: null },
    spec: specOf(project.source, inputs.trackedFiles),
    capabilities: capabilitiesOf.get(project.id) ?? [],
    platformReason: platformReasons.get(project.id) ?? null,
    hasConfigFile: configFiles.has(project.source === "." ? "moon.yml" : `${project.source}/moon.yml`),
  }));

  const shared = new Set(
    [...capabilitiesOf].filter(([, ids]) => ids.length > 1).map(([component]) => component),
  );
  const capabilities: Capability[] = inputs.capabilityFile.capabilities.map((capability) => {
    const components = componentsOf.get(capability.id) ?? [];
    return {
      ...capability,
      components,
      commits: distinctCommits(inputs.commits, sources, components),
      sharedComponents: components.filter((id) => shared.has(id)).sort(),
      specs: inputs.specsByCapability.get(capability.id) ?? [],
    };
  });

  const coupling = markUndeclared(stats.coupling, projectEdges);
  const dates = inputs.commits.map((c) => c.date).sort();

  return {
    generatedAt: inputs.generatedAt,
    commit: inputs.commit,
    history: {
      limit: inputs.historyLimit,
      commits: inputs.commits.length,
      since: dates[0] ?? null,
      until: dates[dates.length - 1] ?? null,
    },
    projects,
    projectEdges,
    taskEdges: graph.taskEdges,
    capabilities,
    coupling,
    gaps: deriveGaps({ projects, projectEdges, taskEdges: graph.taskEdges, capabilities, coupling }),
  };
}

/** The data contract between the explorer's generator and its rendered site. */

/** Fewest co-changes before a pair is worth reporting. One shared commit is a coincidence. */
export const MIN_CO_CHANGE_COMMITS = 2;

/** How strongly a declared project edge participates in Moon's task hashing. */
export type EdgeStrength = "direct" | "transitive" | "declared-only";

export interface ProjectSpec {
  features: string[];
  decisions: string[];
  mocks: string[];
}

export interface ProjectChange {
  commits: number;
  files: number;
  lastChanged: string | null;
}

export interface ProjectTask {
  id: string;
  target: string;
  description: string | null;
  outputs: string[];
  cache: boolean;
  runInCI: boolean;
}

export interface ProjectNode {
  id: string;
  source: string;
  language: string;
  layer: string;
  toolchains: string[];
  tasks: ProjectTask[];
  change: ProjectChange;
  spec: ProjectSpec;
  capabilities: string[];
  platformReason: string | null;
  /** False when moon discovered the project from `projects.globs` alone, with no `moon.yml` of its own. */
  hasConfigFile: boolean;
}

export interface ProjectEdge {
  from: string;
  to: string;
  scope: string;
  strength: EdgeStrength;
  /** The `<from-task> -> <to-task>` pairs Moon folds into the dependent's hash. */
  hashingTaskDeps: string[];
  /** The `<from-task> -> <to-task>` pairs Moon records as `ignored`. */
  ignoredTaskDeps: string[];
}

export interface TaskEdge {
  from: string;
  to: string;
  /** False when the upstream task declares no `outputs`, so Moon ignores it for hashing. */
  hashing: boolean;
}

export interface Capability {
  id: string;
  name: string;
  description: string;
  components: string[];
  /** Commits in the history window that touched any of this capability's components. */
  commits: number;
  /** Components that this capability shares with at least one other capability. */
  sharedComponents: string[];
  /** e2e specs tagged with this capability, as `<file> › <title>`. */
  specs: string[];
}

export interface CouplingPair {
  a: string;
  b: string;
  commits: number;
  /** True when neither project declares a dependency on the other, directly or transitively. */
  undeclared: boolean;
}

/** One honest limitation of the generated graph, derived rather than asserted. */
export interface Gap {
  id: string;
  title: string;
  explanation: string;
  items: string[];
}

export interface History {
  limit: number;
  commits: number;
  since: string | null;
  until: string | null;
}

export interface ExplorerModel {
  generatedAt: string;
  commit: string;
  history: History;
  projects: ProjectNode[];
  projectEdges: ProjectEdge[];
  taskEdges: TaskEdge[];
  capabilities: Capability[];
  coupling: CouplingPair[];
  gaps: Gap[];
}
// Exercise: an explorer TypeScript change, to measure what CI rebuilds.

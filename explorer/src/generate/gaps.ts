/** Derives the explorer's honesty panel: what the generated graph provably cannot see. */

import {
  MIN_CO_CHANGE_COMMITS,
  type Capability,
  type CouplingPair,
  type Gap,
  type ProjectEdge,
  type ProjectNode,
  type TaskEdge,
} from "../model.ts";

export interface GapInputs {
  projects: ProjectNode[];
  projectEdges: ProjectEdge[];
  taskEdges: TaskEdge[];
  capabilities: Capability[];
  coupling: CouplingPair[];
}

function connectedComponents(ids: string[], edges: { from: string; to: string }[]): string[][] {
  const members = new Set(ids);
  const neighbours = new Map<string, Set<string>>();
  for (const id of ids) neighbours.set(id, new Set());
  for (const { from, to } of edges) {
    if (!members.has(from) || !members.has(to)) continue;
    neighbours.get(from)?.add(to);
    neighbours.get(to)?.add(from);
  }
  const seen = new Set<string>();
  const groups: string[][] = [];
  for (const id of ids) {
    if (seen.has(id)) continue;
    const group: string[] = [];
    const queue = [id];
    seen.add(id);
    while (queue.length > 0) {
      const current = queue.pop() as string;
      group.push(current);
      for (const next of neighbours.get(current) ?? []) {
        if (seen.has(next)) continue;
        seen.add(next);
        queue.push(next);
      }
    }
    groups.push(group.sort());
  }
  return groups;
}

export function deriveGaps(inputs: GapInputs): Gap[] {
  const { projects, projectEdges, taskEdges, capabilities, coupling } = inputs;

  const declarationOnly = projectEdges.filter((edge) => edge.strength === "declared-only");
  const ignoredTaskDeps = taskEdges.filter((edge) => !edge.hashing);
  const uncached = projects.flatMap((project) =>
    project.tasks.filter((task) => !task.cache).map((task) => task.target),
  );
  const taskless = projects.filter((project) => project.tasks.length === 0).map((project) => project.id);
  const globDiscovered = projects.filter((project) => !project.hasConfigFile).map((project) => project.id);
  const untested = capabilities.filter((capability) => capability.specs.length === 0).map((c) => c.id);
  const hiddenCoupling = coupling.filter(
    (pair) => pair.undeclared && pair.commits >= MIN_CO_CHANGE_COMMITS,
  );
  const split = capabilities
    .map((capability) => ({
      capability,
      groups: connectedComponents(capability.components, projectEdges),
    }))
    .filter((entry) => entry.groups.length > 1);

  return [
    {
      id: "declaration-only-edges",
      title: "Declared edges that cannot invalidate a cache",
      explanation:
        "Moon folds an upstream task's hash into its dependent only when that upstream task declares outputs. " +
        "These project edges order work and drive affected-detection, but no output-declaring task dep sits behind them, " +
        "so a cached downstream task can replay a pass the upstream change should have invalidated. " +
        "See spec/decisions/adr-0006-task-deps-on-output-declaring-tasks.md.",
      items: declarationOnly.map(
        (edge) =>
          `${edge.from} -> ${edge.to}` +
          (edge.ignoredTaskDeps.length > 0 ? ` (ignored: ${edge.ignoredTaskDeps.join(", ")})` : ""),
      ),
    },
    {
      id: "ignored-task-deps",
      title: "Task deps Moon records as `ignored`",
      explanation:
        "The upstream task declares no outputs, so `moon hash` prints the literal word `ignored` next to it. " +
        "The dependency still sequences the two tasks. It contributes nothing to the dependent's cache key.",
      items: ignoredTaskDeps.map((edge) => `${edge.from} -> ${edge.to}`),
    },
    {
      id: "uncached-tasks",
      title: "Tasks Moon does not cache",
      explanation:
        "These tasks set `cache: false`, because their real result is not a file Moon can hash — a Docker image " +
        "in the local daemon, a database Moon never sees, or a report derived from git history. Nothing about " +
        "their freshness is tracked here; the underlying tool's own cache is the only guard.",
      items: uncached,
    },
    {
      id: "taskless-projects",
      title: "Projects with no tasks",
      explanation:
        "A project with no task cannot be affected by anything and cannot fail a build. " +
        "A change inside one is invisible to `moon ci` unless another project declares its files.",
      items: taskless,
    },
    {
      id: "glob-discovered-projects",
      title: "Projects Moon discovered from a directory, not from a `moon.yml`",
      explanation:
        "`.moon/workspace.yml` sets `projects.globs: [\"*\"]`, so every top-level directory is a project whether " +
        "or not it carries a `moon.yml`. This generator declares the `moon.yml` files as inputs and can declare " +
        "nothing for a directory that has none, so adding one moves no task hash: under `moon ci` this site is " +
        "not regenerated at all, and the capability check that would reject the new project never runs. " +
        "This list is empty by construction on any build that got this far, because that same check refuses a " +
        "project with no capability claim and a claim needs a `moon.yml` to live in. Read it as the shape of " +
        "what is missing, not as a count: the two mechanisms hold each other up, and `moon ci` can skip both. " +
        "See explorer/spec/decisions/adr-0004-the-project-graph-is-more-than-the-moon-yml-files.md.",
      items: globDiscovered,
    },
    {
      id: "capabilities-without-e2e",
      title: "Capabilities no e2e spec claims",
      explanation:
        "Read from `playwright test --list --reporter=json`, so it tracks the suite rather than a second list of " +
        "it. A capability with no tagged journey is not proven end to end. This is reported and not failed on " +
        "purpose: failing would buy a hollow spec, and this is the `where to invest next` signal seed.md §9 asks " +
        "the zoomed-out view to carry. Run one capability's journeys with " +
        "`moon run e2e:test -- --grep @capability/<id>`.",
      items: untested,
    },
    {
      id: "undeclared-co-change",
      title: "Projects that change together with no edge between them",
      explanation:
        "Derived from git history, not from the graph. Two projects repeatedly edited in the same commit, " +
        "with no declared dependency in either direction, is the shape a runtime-only edge leaves behind. " +
        "It is a question to ask, not a proven dependency. A commit touching more than a third of the " +
        "components is not counted: it pairs everything with everything and says nothing.",
      items: hiddenCoupling.map((pair) => `${pair.a} + ${pair.b} (${pair.commits} commits)`),
    },
    {
      id: "split-capabilities",
      title: "Capabilities whose components are not connected by build edges",
      explanation:
        "A capability delivered by components with no declared edge between them is the pre-consolidation shape " +
        "seed.md §9 describes: the components genuinely talk, over HTTP, and the graph cannot see it. " +
        "An empty list here is the result seed.md §6 is after, not an absence of evidence.",
      items: split.map((entry) => `${entry.capability.id}: ${entry.groups.map((g) => g.join("+")).join(" | ")}`),
    },
  ];
}

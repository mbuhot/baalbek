/** The zoomed-in view: the real project graph, and the task graph behind it. */

import cytoscape, { type ElementDefinition } from "cytoscape";
import type { ExplorerModel } from "../model.ts";
import { clear, el } from "./dom.ts";
import { renderDetail } from "./detail.ts";
import { heatBucket } from "./rank.ts";

export type GraphMode = "projects" | "tasks";

const LANGUAGE_COLOURS: Record<string, string> = {
  elixir: "#a78bfa",
  rust: "#fb923c",
  gleam: "#f472b6",
  typescript: "#38bdf8",
  bash: "#94a3b8",
  system: "#94a3b8",
  unknown: "#64748b",
};

export function projectElements(model: ExplorerModel): ElementDefinition[] {
  const maxCommits = Math.max(...model.projects.map((p) => p.change.commits), 1);
  const nodes: ElementDefinition[] = model.projects.map((project) => ({
    data: {
      id: project.id,
      label: project.id,
      colour: LANGUAGE_COLOURS[project.language] ?? LANGUAGE_COLOURS["unknown"],
      size: 26 + heatBucket(project.change.commits, maxCommits) * 9,
    },
  }));
  const edges: ElementDefinition[] = model.projectEdges.map((edge) => ({
    data: { id: `${edge.from}->${edge.to}`, source: edge.from, target: edge.to, strength: edge.strength },
    classes: edge.strength,
  }));
  return [...nodes, ...edges];
}

export function taskElements(model: ExplorerModel): ElementDefinition[] {
  const targets = new Set<string>();
  for (const project of model.projects) for (const task of project.tasks) targets.add(task.target);
  const outputs = new Map<string, number>();
  for (const project of model.projects) for (const task of project.tasks) outputs.set(task.target, task.outputs.length);

  const nodes: ElementDefinition[] = [...targets].sort().map((target) => ({
    data: {
      id: target,
      label: target,
      colour: (outputs.get(target) ?? 0) > 0 ? "#4ade80" : "#64748b",
      size: 18,
    },
    classes: "task",
  }));
  const edges: ElementDefinition[] = model.taskEdges
    .filter((edge) => targets.has(edge.from) && targets.has(edge.to))
    .map((edge) => ({
      data: { id: `${edge.from}->${edge.to}`, source: edge.from, target: edge.to },
      classes: edge.hashing ? "direct" : "declared-only",
    }));
  return [...nodes, ...edges];
}

const STYLE: cytoscape.StylesheetJson = [
  {
    selector: "node",
    style: {
      "background-color": "data(colour)",
      width: "data(size)",
      height: "data(size)",
      label: "data(label)",
      color: "#e2e8f0",
      "font-size": 11,
      "font-family": "ui-monospace, SFMono-Regular, Menlo, monospace",
      "text-valign": "bottom",
      "text-margin-y": 4,
      "text-outline-color": "#0b1120",
      "text-outline-width": 2,
    },
  },
  {
    selector: "node.task",
    style: { "text-valign": "center", "text-halign": "right", "text-margin-x": 6, "text-margin-y": 0 },
  },
  { selector: "node:selected", style: { "border-width": 3, "border-color": "#fde047" } },
  {
    selector: "edge",
    style: {
      width: 2,
      "curve-style": "bezier",
      "target-arrow-shape": "triangle",
      "arrow-scale": 0.9,
    },
  },
  { selector: "edge.direct", style: { "line-color": "#4ade80", "target-arrow-color": "#4ade80" } },
  {
    selector: "edge.transitive",
    style: { "line-color": "#facc15", "target-arrow-color": "#facc15", "line-style": "dashed" },
  },
  {
    selector: "edge.declared-only",
    style: { "line-color": "#f87171", "target-arrow-color": "#f87171", "line-style": "dotted", width: 3 },
  },
];

// Both are ranked. The task graph is transposed so its ranks run left to
// right, because `project:task` labels collide when stacked in a row.
const LAYOUT: Record<GraphMode, cytoscape.LayoutOptions> = {
  projects: { name: "breadthfirst", directed: true, spacingFactor: 1.25, padding: 30, avoidOverlap: true },
  tasks: {
    name: "breadthfirst",
    directed: true,
    // Task labels sit to the right of their node and are long; below ~1.6 they overlap the next rank.
    spacingFactor: 1.8,
    padding: 30,
    avoidOverlap: true,
    transform: (_node, position) => ({ x: position.y, y: position.x }),
  },
};

const HEADING: Record<GraphMode, { title: string; lede: string }> = {
  projects: {
    title: "Project graph",
    lede:
      "Generated from `moon project-graph --json` on every build. Edge colour is not decoration: it says " +
      "whether the edge can actually invalidate a cache.",
  },
  tasks: {
    title: "Task graph",
    lede:
      "Generated from `moon task-graph --json` on every build. A green node declares `outputs`, so a task " +
      "depending on it folds its hash in; a grey node declares none, and `moon hash` prints `ignored`.",
  },
};

const LEGEND: Record<GraphMode, [string, string][]> = {
  projects: [
    ["direct", "Hash propagates: a task here depends on an output-declaring task there"],
    ["transitive", "Hash propagates, but only through another project"],
    ["declared-only", "Declared in moon.yml, invisible to hashing — a cache hit can go stale"],
  ],
  tasks: [
    ["direct", "Upstream task declares outputs, so its hash is folded in"],
    ["declared-only", "Upstream task declares no outputs — `moon hash` prints `ignored`"],
  ],
};

export function renderGraph(host: HTMLElement, model: ExplorerModel, focus: string | null): void {
  clear(host);
  let mode: GraphMode = "projects";

  const controls = el("div", { class: "controls" });
  const canvas = el("div", { class: "cy" });
  const legend = el("ul", { class: "legend" });
  const detail = el("aside", { class: "detail" });
  const heading = el("h2", {}, HEADING[mode].title);
  const lede = el("p", { class: "lede" }, HEADING[mode].lede);

  const drawLegend = (): void => {
    clear(legend);
    for (const [kind, text] of LEGEND[mode]) {
      legend.append(el("li", {}, el("span", { class: `swatch ${kind}` }), text));
    }
  };

  let cy: cytoscape.Core | null = null;
  const draw = (): void => {
    heading.textContent = HEADING[mode].title;
    lede.textContent = HEADING[mode].lede;
    cy?.destroy();
    cy = cytoscape({
      container: canvas,
      elements: mode === "projects" ? projectElements(model) : taskElements(model),
      style: STYLE,
      layout: LAYOUT[mode],
      wheelSensitivity: 0.2,
    });
    cy.on("tap", "node", (event) => {
      const id = String(event.target.id());
      renderDetail(detail, model, mode === "projects" ? id : (id.split(":")[0] ?? id));
    });
    drawLegend();
  };

  for (const option of [
    { id: "projects" as const, label: "Project graph" },
    { id: "tasks" as const, label: "Task graph" },
  ]) {
    const button = el("button", { type: "button", "aria-pressed": String(option.id === mode) }, option.label);
    button.addEventListener("click", () => {
      mode = option.id;
      for (const other of controls.querySelectorAll("button")) {
        other.setAttribute("aria-pressed", String(other.textContent === option.label));
      }
      draw();
    });
    controls.append(button);
  }

  host.append(
    heading,
    lede,
    controls,
    el("div", { class: "graph-layout" }, el("div", {}, canvas, legend), detail),
  );

  draw();
  renderDetail(detail, model, focus);
}

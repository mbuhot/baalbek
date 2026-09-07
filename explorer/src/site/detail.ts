/** The zoomed-in panel: one component's tasks, edges, change history, and spec directory. */

import type { ExplorerModel, ProjectEdge } from "../model.ts";
import { append, clear, el, repoLink } from "./dom.ts";

const STRENGTH_NOTE: Record<ProjectEdge["strength"], string> = {
  direct: "hashed directly",
  transitive: "hashed through another project",
  "declared-only": "ordering only — no hash reaches this edge",
};

function edgeLine(edge: ProjectEdge, other: string): HTMLElement {
  return el(
    "li",
    { class: `edge-${edge.strength}` },
    el("span", { class: "edge-peer" }, other),
    el("span", { class: "edge-note" }, STRENGTH_NOTE[edge.strength]),
    edge.ignoredTaskDeps.length > 0
      ? el("span", { class: "edge-ignored" }, `ignored: ${edge.ignoredTaskDeps.join(", ")}`)
      : null,
  );
}

function specList(title: string, paths: string[]): HTMLElement | null {
  if (paths.length === 0) return null;
  return el("div", {}, el("h4", {}, title), el("ul", { class: "specs" }, ...paths.map((p) => el("li", {}, repoLink(p)))));
}

export function renderDetail(host: HTMLElement, model: ExplorerModel, id: string | null): void {
  clear(host);
  if (id === null) {
    host.append(el("p", { class: "empty" }, "Select a node to see its tasks, edges, and specification."));
    return;
  }
  const project = model.projects.find((p) => p.id === id);
  if (project === undefined) {
    host.append(el("p", { class: "empty" }, `No project named ${id}.`));
    return;
  }

  const dependsOn = model.projectEdges.filter((edge) => edge.from === id);
  const dependedOnBy = model.projectEdges.filter((edge) => edge.to === id);

  const tasks = project.tasks.map((task) =>
    el(
      "tr",
      {},
      el("td", {}, task.id),
      el("td", { class: "mono" }, task.outputs.length > 0 ? task.outputs.join(", ") : "—"),
      el(
        "td",
        {},
        [task.cache ? null : "uncached", task.runInCI ? null : "local only"]
          .filter((note) => note !== null)
          .join(", ") || "—",
      ),
    ),
  );

  append(
    host,
    el("h3", {}, project.id),
    el(
      "p",
      { class: "meta" },
      `${project.language} · layer ${project.layer} · ${project.source}/`,
      project.toolchains.length > 0 ? ` · toolchains: ${project.toolchains.join(", ")}` : "",
    ),
    project.platformReason !== null
      ? el("p", { class: "platform" }, `Platform. ${project.platformReason}`)
      : el("p", { class: "caps" }, `Capabilities: ${project.capabilities.join(", ")}`),
    el(
      "p",
      { class: "meta" },
      `${project.change.commits} commits, ${project.change.files} file changes` +
        (project.change.lastChanged !== null ? `, last ${project.change.lastChanged.slice(0, 10)}` : ""),
    ),
    project.tasks.length > 0
      ? el(
          "table",
          { class: "tasks" },
          el(
            "thead",
            {},
            el("tr", {}, el("th", {}, "Task"), el("th", {}, "Declared outputs"), el("th", {}, "Caching")),
          ),
          el("tbody", {}, ...tasks),
        )
      : el("p", { class: "warn" }, "No tasks. Nothing in this project can be affected, built, or failed by moon."),
    dependsOn.length > 0
      ? el("div", {}, el("h4", {}, "Depends on"), el("ul", { class: "edges" }, ...dependsOn.map((e) => edgeLine(e, e.to))))
      : null,
    dependedOnBy.length > 0
      ? el(
          "div",
          {},
          el("h4", {}, "Depended on by"),
          el("ul", { class: "edges" }, ...dependedOnBy.map((e) => edgeLine(e, e.from))),
        )
      : null,
    specList("Acceptance criteria", project.spec.features),
    specList("Decisions", project.spec.decisions),
    specList("Mocks", project.spec.mocks),
  );
}

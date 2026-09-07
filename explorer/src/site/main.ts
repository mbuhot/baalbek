/** Entry point: the three views, and the header that says when and from what the site was generated. */

import "./style.css";
import { model } from "./data.ts";
import { clear, el } from "./dom.ts";
import { renderCapabilities } from "./capability-view.ts";
import { renderGraph } from "./graph-view.ts";
import { renderGaps } from "./gaps-view.ts";

type ViewId = "capabilities" | "graph" | "gaps";

const VIEWS: { id: ViewId; label: string; audience: string }[] = [
  { id: "capabilities", label: "Capabilities", audience: "zoomed out" },
  { id: "graph", label: "Project graph", audience: "zoomed in" },
  { id: "gaps", label: "Blind spots", audience: "honest" },
];

const app = document.getElementById("app");
if (app === null) throw new Error("missing #app");

const main = el("main", {});
const nav = el("nav", {});
let current: ViewId = "capabilities";

function show(view: ViewId, focus: string | null = null): void {
  current = view;
  for (const button of nav.querySelectorAll("button")) {
    button.setAttribute("aria-pressed", String(button.getAttribute("data-view") === view));
  }
  clear(main);
  if (view === "capabilities") renderCapabilities(main, model, (id) => show("graph", id));
  else if (view === "graph") renderGraph(main, model, focus);
  else renderGaps(main, model);
}

for (const view of VIEWS) {
  const button = el("button", { type: "button", "data-view": view.id }, view.label, el("small", {}, view.audience));
  button.addEventListener("click", () => show(view.id));
  nav.append(button);
}

app.append(
  el(
    "header",
    {},
    el("h1", {}, "Baalbek architecture explorer"),
    el(
      "p",
      { class: "provenance" },
      `Generated ${model.generatedAt.slice(0, 16).replace("T", " ")} UTC from commit ${model.commit.slice(0, 8)} · ` +
        `${model.projects.length} projects, ${model.projectEdges.length} declared edges · ` +
        `${model.history.commits} commits of history`,
    ),
    nav,
    el(
      "p",
      { class: "banner" },
      "Declared build edges only. ",
      (() => {
        const link = el("button", { type: "button", class: "linkish" }, "What this cannot see");
        link.addEventListener("click", () => show("gaps"));
        return link;
      })(),
    ),
  ),
  main,
);

show(current);

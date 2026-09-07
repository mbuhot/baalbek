/** The honesty view: what the generated graph provably cannot see. */

import type { ExplorerModel } from "../model.ts";
import { clear, el } from "./dom.ts";

export function renderGaps(host: HTMLElement, model: ExplorerModel): void {
  clear(host);
  host.append(
    el("h2", {}, "Blind spots"),
    el(
      "p",
      { class: "lede" },
      "This graph is built from declared build edges and nothing else. A call made over HTTP, a shared " +
        "database table, a copied constant — none of them appear anywhere on this site. That is the argument " +
        "for the playbook, not a defect in the drawing: distribution is what made the architecture invisible.",
    ),
    el(
      "p",
      { class: "lede" },
      "Everything below is derived from the same inputs as the graph. Nothing here is hand-written, " +
        "so it cannot quietly stop being true.",
    ),
  );

  for (const gap of model.gaps) {
    host.append(
      el(
        "section",
        { class: `gap ${gap.items.length === 0 ? "clean" : ""}` },
        el("h3", {}, `${gap.title} — ${gap.items.length}`),
        el("p", { class: "desc" }, gap.explanation),
        gap.items.length === 0
          ? el("p", { class: "none" }, "None found in this build.")
          : el("ul", { class: "gap-items" }, ...gap.items.map((item) => el("li", { class: "mono" }, item))),
      ),
    );
  }
}

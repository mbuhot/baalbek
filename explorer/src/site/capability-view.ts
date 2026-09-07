/** The zoomed-out view: capabilities, with change-frequency and coupling overlays. */

import { MIN_CO_CHANGE_COMMITS, type ExplorerModel } from "../model.ts";
import { clear, el } from "./dom.ts";
import { heatBucket, rankCapabilities, type Overlay } from "./rank.ts";

const OVERLAYS: { id: Overlay; label: string; caption: string }[] = [
  {
    id: "change",
    label: "Change frequency",
    caption: "Commits in the history window that touched any component of the capability.",
  },
  {
    id: "coupling",
    label: "Coupling",
    caption:
      "Co-change weight crossing the capability's boundary: for every pair of components on opposite " +
      "sides, the commits that touched both. A commit touching more than a third of the components " +
      "is not counted — it pairs everything with everything.",
  },
];

function componentChip(model: ExplorerModel, id: string, maxCommits: number): HTMLElement {
  const project = model.projects.find((p) => p.id === id);
  const commits = project?.change.commits ?? 0;
  const shared = (project?.capabilities.length ?? 0) > 1;
  return el(
    "span",
    { class: `chip heat-${heatBucket(commits, maxCommits)}`, title: `${commits} commits — ${project?.language ?? "?"}` },
    id,
    shared ? el("span", { class: "shared", title: "Serves more than one capability" }, "*") : null,
  );
}

export function renderCapabilities(host: HTMLElement, model: ExplorerModel, onComponent: (id: string) => void): void {
  clear(host);
  let overlay: Overlay = "change";

  const controls = el("div", { class: "controls" });
  const caption = el("p", { class: "caption" });
  const grid = el("div", { class: "grid" });
  const ranking = el("ol", { class: "ranking" });
  // Scaled against the components drawn here only: `root` owns every top-level file and flattens the scale.
  const drawn = new Set(model.capabilities.flatMap((capability) => capability.components));
  const maxCommits = Math.max(
    ...model.projects.filter((p) => drawn.has(p.id)).map((p) => p.change.commits),
    1,
  );

  const draw = (): void => {
    const ranked = rankCapabilities(model, overlay);
    const max = Math.max(...ranked.map((r) => r.score), 1);
    caption.textContent = OVERLAYS.find((o) => o.id === overlay)?.caption ?? "";

    clear(grid);
    for (const { capability, change, coupling, score } of ranked) {
      const chips = el("div", { class: "chips" });
      for (const component of capability.components) {
        const chip = componentChip(model, component, maxCommits);
        chip.addEventListener("click", () => onComponent(component));
        chips.append(chip);
      }
      grid.append(
        el(
          "article",
          { class: `card heat-border-${heatBucket(score, max)}` },
          el("h3", {}, capability.name),
          el("p", { class: "desc" }, capability.description),
          chips,
          el(
            "p",
            { class: "metrics" },
            `${change} commits · ${coupling} cross-capability co-changes · ` +
              (capability.specs.length > 0
                ? `${capability.specs.length} e2e spec${capability.specs.length === 1 ? "" : "s"}`
                : "no e2e coverage"),
          ),
        ),
      );
    }

    clear(ranking);
    for (const { capability, score } of ranked) {
      ranking.append(
        el(
          "li",
          {},
          el("span", { class: "rank-name" }, capability.name),
          el("span", { class: "bar", style: `width:${Math.round((score / max) * 100)}%` }),
          el("span", { class: "rank-value" }, String(score)),
        ),
      );
    }
  };

  clear(controls);
  for (const option of OVERLAYS) {
    const button = el("button", { type: "button", "data-overlay": option.id }, option.label);
    button.addEventListener("click", () => {
      overlay = option.id;
      for (const other of controls.querySelectorAll("button")) {
        other.setAttribute("aria-pressed", String(other.getAttribute("data-overlay") === overlay));
      }
      draw();
    });
    button.setAttribute("aria-pressed", String(option.id === overlay));
    controls.append(button);
  }

  const couplingRows = model.coupling
    .filter((pair) => pair.commits >= MIN_CO_CHANGE_COMMITS)
    .slice(0, 12)
    .map((pair) =>
      el(
        "tr",
        { class: pair.undeclared ? "undeclared" : "" },
        el("td", {}, pair.a),
        el("td", {}, pair.b),
        el("td", {}, String(pair.commits)),
        el("td", {}, pair.undeclared ? "no declared edge" : "declared"),
      ),
    );

  host.append(
    el("h2", {}, "Capability map"),
    el(
      "p",
      { class: "lede" },
      "capabilities.yml names the capabilities and nothing else. Each component claims the ones it serves " +
        "as a tag in its own moon.yml, and each e2e spec claims them as a Playwright tag, so a claim on a " +
        "capability nobody defined fails the build. Change frequency and coupling come from git history.",
    ),
    controls,
    caption,
    grid,
    el("h3", {}, "Where the change is"),
    ranking,
    el("h3", {}, "Components that change together"),
    el(
      "table",
      { class: "coupling" },
      el(
        "thead",
        {},
        el("tr", {}, el("th", {}, "Component"), el("th", {}, "Component"), el("th", {}, "Commits"), el("th", {}, "Build edge")),
      ),
      el("tbody", {}, ...couplingRows),
    ),
  );
  draw();
}

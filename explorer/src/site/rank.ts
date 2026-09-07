/** Pure ranking and shading helpers behind the zoomed-out overlays. */

import type { Capability, CouplingPair, ExplorerModel } from "../model.ts";

/** Buckets a value into 0..4 for the heat classes the stylesheet defines. */
export function heatBucket(value: number, max: number): number {
  if (max <= 0 || value <= 0) return 0;
  return Math.min(4, Math.ceil((value / max) * 4));
}

/** Co-change commits between the components of a capability and everything outside it. */
export function externalCoupling(capability: Capability, coupling: CouplingPair[]): number {
  const inside = new Set(capability.components);
  return coupling
    .filter((pair) => inside.has(pair.a) !== inside.has(pair.b))
    .reduce((total, pair) => total + pair.commits, 0);
}

export type Overlay = "change" | "coupling";

export interface RankedCapability {
  capability: Capability;
  change: number;
  coupling: number;
  score: number;
}

/** Orders capabilities by the selected overlay, breaking ties by name so the list is stable. */
export function rankCapabilities(model: ExplorerModel, overlay: Overlay): RankedCapability[] {
  return model.capabilities
    .map((capability) => {
      const change = capability.commits;
      const coupling = externalCoupling(capability, model.coupling);
      return { capability, change, coupling, score: overlay === "change" ? change : coupling };
    })
    .sort((a, b) => b.score - a.score || a.capability.name.localeCompare(b.capability.name));
}

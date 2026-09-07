/** The generated model, bundled into the site so the page fetches nothing at runtime. */

import type { ExplorerModel } from "../model.ts";
import raw from "../generated/model.json";

// `buildModel` is typed to return `ExplorerModel`, so the shape is checked
// where it is produced; `resolveJsonModule` only recovers a structural echo of it.
export const model = raw as unknown as ExplorerModel;

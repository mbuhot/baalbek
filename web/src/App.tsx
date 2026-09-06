import { useState } from "preact/hooks";
import { DispatchBoard } from "./components/DispatchBoard";
import { TechnicianView } from "./components/TechnicianView";

type Tab = "dispatch" | "technician";

/** The PWA's root: switches between the dispatch board and the technician work-queue view. */
export function App() {
  const [tab, setTab] = useState<Tab>("dispatch");

  return (
    <main>
      <h1>Baalbek Dispatch</h1>
      <nav>
        <button type="button" aria-pressed={tab === "dispatch"} onClick={() => setTab("dispatch")}>
          Dispatch board
        </button>
        <button type="button" aria-pressed={tab === "technician"} onClick={() => setTab("technician")}>
          Technician view
        </button>
      </nav>
      {tab === "dispatch" ? <DispatchBoard /> : <TechnicianView />}
    </main>
  );
}

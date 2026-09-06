import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/preact";
import { mockJsonRoutes } from "../test/mockFetch";
import { jobFixture, workOrderFixture } from "../test/fixtures";
import { TechnicianView } from "./TechnicianView";

describe("TechnicianView", () => {
  it("renders a work order joined to its job", async () => {
    mockJsonRoutes([
      { path: "/api/json/core/work_orders", body: { data: [workOrderFixture] } },
      { path: "/api/json/core/jobs", body: { data: [jobFixture] } },
    ]);

    render(<TechnicianView />);

    expect(await screen.findByText("Filter replaced, unit tested")).toBeInTheDocument();
    expect(screen.getByText("Replace HVAC filter")).toBeInTheDocument();
    expect(screen.getByText("open")).toBeInTheDocument();
  });

  it("sorts completed work orders after open ones", async () => {
    const completed = {
      ...workOrderFixture,
      id: "w2",
      attributes: { ...workOrderFixture.attributes!, status: "completed" as const, summary: "Done job" },
    };

    mockJsonRoutes([
      { path: "/api/json/core/work_orders", body: { data: [completed, workOrderFixture] } },
      { path: "/api/json/core/jobs", body: { data: [jobFixture] } },
    ]);

    render(<TechnicianView />);

    const rows = await screen.findAllByRole("row");
    // rows[0] is the header row.
    expect(rows[1]).toHaveTextContent("Filter replaced, unit tested");
    expect(rows[2]).toHaveTextContent("Done job");
  });
});

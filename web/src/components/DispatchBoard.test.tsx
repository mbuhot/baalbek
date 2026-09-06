import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/preact";
import { mockJsonRoutes } from "../test/mockFetch";
import { customerFixture, jobFixture, siteFixture } from "../test/fixtures";
import { DispatchBoard } from "./DispatchBoard";

describe("DispatchBoard", () => {
  it("renders a job joined to its site and customer", async () => {
    mockJsonRoutes([
      { path: "/api/json/core/jobs", body: { data: [jobFixture] } },
      { path: "/api/json/core/sites", body: { data: [siteFixture] } },
      { path: "/api/json/core/customers", body: { data: [customerFixture] } },
    ]);

    render(<DispatchBoard />);

    expect(await screen.findByText("Replace HVAC filter")).toBeInTheDocument();
    expect(screen.getByText("Acme Warehouse")).toBeInTheDocument();
    expect(screen.getByText("Acme Corp")).toBeInTheDocument();
    expect(screen.getByText("scheduled")).toBeInTheDocument();
  });

  it("renders an error message when the API fails", async () => {
    mockJsonRoutes([
      { path: "/api/json/core/jobs", status: 500, body: { errors: [] } },
      { path: "/api/json/core/sites", body: { data: [] } },
      { path: "/api/json/core/customers", body: { data: [] } },
    ]);

    render(<DispatchBoard />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Failed to load dispatch data.");
  });

  it("renders an empty state with no jobs", async () => {
    mockJsonRoutes([
      { path: "/api/json/core/jobs", body: { data: [] } },
      { path: "/api/json/core/sites", body: { data: [] } },
      { path: "/api/json/core/customers", body: { data: [] } },
    ]);

    render(<DispatchBoard />);

    expect(await screen.findByText("No jobs yet.")).toBeInTheDocument();
  });
});

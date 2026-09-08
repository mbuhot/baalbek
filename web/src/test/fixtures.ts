import type { Customer, Job, Site, WorkOrder } from "core-api-client";

/** JSON:API fixture resource objects, typed against the generated schema so a real API shape drift fails here too. */

const timestamps = { inserted_at: "2026-09-08T00:00:00Z", updated_at: "2026-09-08T00:00:00Z" };

export const customerFixture: Customer = {
  type: "customer",
  id: "c1",
  attributes: { name: "Acme Corp", email: "ops@acme.test", phone: null, ...timestamps },
};

export const siteFixture: Site = {
  type: "site",
  id: "s1",
  attributes: { name: "Acme Warehouse", address: "1 Dock Rd", customer_id: "c1", ...timestamps },
};

export const jobFixture: Job = {
  type: "job",
  id: "j1",
  attributes: {
    title: "Replace HVAC filter",
    description: "Quarterly filter swap.",
    status: "scheduled",
    scheduled_at: "2026-09-10T09:00:00Z",
    site_id: "s1",
    ...timestamps,
  },
};

export const workOrderFixture: WorkOrder = {
  type: "work_order",
  id: "w1",
  attributes: {
    summary: "Filter replaced, unit tested",
    status: "open",
    completed_at: null,
    job_id: "j1",
    ...timestamps,
  },
};

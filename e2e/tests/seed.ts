import type { APIRequestContext } from "@playwright/test";

/** Creates real rows through the release's JSON:API — the only way this suite gets data. */

const CORE_API = "/api/json/core";

const JSON_API_HEADERS = {
  "content-type": "application/vnd.api+json",
  accept: "application/vnd.api+json",
};

/** Every run shares one database, so names carry a per-call suffix and tests assert on their own rows only. */
export function unique(label: string): string {
  return `${label}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

async function create(
  request: APIRequestContext,
  path: string,
  type: string,
  attributes: Record<string, unknown>,
): Promise<string> {
  const response = await request.post(`${CORE_API}/${path}`, {
    headers: JSON_API_HEADERS,
    data: { data: { type, attributes } },
  });

  if (response.status() !== 201) {
    throw new Error(`POST ${CORE_API}/${path} returned ${response.status()}: ${await response.text()}`);
  }

  const body = (await response.json()) as { data: { id: string } };
  return body.data.id;
}

export function createCustomer(request: APIRequestContext, name: string): Promise<string> {
  return create(request, "customers", "customer", { name, email: `${name}@example.test` });
}

export function createSite(request: APIRequestContext, name: string, customerId: string): Promise<string> {
  return create(request, "sites", "site", { name, address: "1 Dock Rd", customer_id: customerId });
}

export function createJob(request: APIRequestContext, title: string, siteId: string): Promise<string> {
  return create(request, "jobs", "job", { title, site_id: siteId });
}

export function createWorkOrder(request: APIRequestContext, summary: string, jobId: string): Promise<string> {
  return create(request, "work_orders", "work_order", { summary, job_id: jobId });
}

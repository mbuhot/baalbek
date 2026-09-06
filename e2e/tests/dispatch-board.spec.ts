import { expect, test } from "@playwright/test";
import { createCustomer, createJob, createSite, unique } from "./seed";

/** The dispatcher's journey: work created through the API appears on the board the PWA renders. */

test("shows a job created through the API, joined to its site and customer", async ({ page, request }) => {
  const customerName = unique("Acme Facilities");
  const siteName = unique("Warehouse");
  const jobTitle = unique("Fix conveyor");

  const customerId = await createCustomer(request, customerName);
  const siteId = await createSite(request, siteName, customerId);
  await createJob(request, jobTitle, siteId);

  // Asserted before navigating, so a board rendered from anything but a live
  // 200 from the release fails here rather than passing on cached markup.
  const jobsResponse = page.waitForResponse(
    (response) => response.url().endsWith("/api/json/core/jobs") && response.status() === 200,
  );

  await page.goto("/");
  await jobsResponse;

  const row = page.getByRole("row", { name: new RegExp(jobTitle) });
  await expect(row).toBeVisible();
  await expect(row).toContainText(siteName);
  await expect(row).toContainText(customerName);
  await expect(row).toContainText("requested");
});

test("reflects a job status change made through the API", async ({ page, request }) => {
  const customerId = await createCustomer(request, unique("Northwind"));
  const siteId = await createSite(request, unique("Depot"), customerId);
  const jobTitle = unique("Replace compressor");
  const jobId = await createJob(request, jobTitle, siteId);

  const patch = await request.patch(`/api/json/core/jobs/${jobId}`, {
    headers: { "content-type": "application/vnd.api+json", accept: "application/vnd.api+json" },
    data: { data: { type: "job", id: jobId, attributes: { status: "scheduled" } } },
  });
  expect(patch.status()).toBe(200);

  await page.goto("/");

  await expect(page.getByRole("row", { name: new RegExp(jobTitle) })).toContainText("scheduled");
});

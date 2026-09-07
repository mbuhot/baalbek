import { expect, test } from "@playwright/test";
import { createCustomer, createJob, createSite, createWorkOrder, unique } from "./seed";

/** The technician's journey: switch to the work queue and find the work order raised against a job. */

test("lists an open work order against its job", {
  tag: ["@capability/technician-work-queue", "@capability/work-order-scheduling"],
}, async ({ page, request }) => {
  const customerId = await createCustomer(request, unique("Globex"));
  const siteId = await createSite(request, unique("Plant"), customerId);
  const jobTitle = unique("Service chiller");
  const jobId = await createJob(request, jobTitle, siteId);
  const summary = unique("Initial visit");
  await createWorkOrder(request, summary, jobId);

  await page.goto("/");
  await page.getByRole("button", { name: "Technician view" }).click();

  const row = page.getByRole("row", { name: new RegExp(summary) });
  await expect(row).toBeVisible();
  await expect(row).toContainText(jobTitle);
  await expect(row).toContainText("open");
});

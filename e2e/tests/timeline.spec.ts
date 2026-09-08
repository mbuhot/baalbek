import { expect, test } from "@playwright/test";
import { unique } from "./seed";

/**
 * The standing check that the release still contains the Gleam code, plus
 * the input validation guarding it.
 *
 * The first test is the standing check: `/api/timeline/...` reaches
 * `timeline_facade`, which calls `timeline`'s compiled Gleam modules, and a
 * release that stops bundling them answers "module :timeline is not
 * available". The second covers `Server.Timeline`'s own guard, which runs in
 * Elixir before any Gleam code is reached.
 */

const JSON_HEADERS = { "content-type": "application/json" };

test("replays an event log into a technician's availability", {
  tag: ["@capability/technician-availability", "@capability/release-assurance"],
}, async ({ request }) => {
  const technicianId = unique("tech");
  const siteId = unique("site");

  for (const event of [
    { kind: "shift_started", occurred_at: 1_000 },
    { kind: "travel_started", occurred_at: 2_000, site_id: siteId },
    { kind: "arrived_on_site", occurred_at: 3_000, site_id: siteId },
  ]) {
    const response = await request.post(`/api/timeline/technicians/${technicianId}/events`, {
      headers: JSON_HEADERS,
      data: event,
    });
    expect(response.status(), await response.text()).toBe(201);
  }

  const availability = await request.get(`/api/timeline/technicians/${technicianId}/availability`);
  expect(availability.status()).toBe(200);

  // The projection is computed by Gleam, from the events above.
  expect(await availability.json()).toMatchObject({
    data: { type: "availability", id: technicianId, attributes: { status: "on_site", site_id: siteId } },
  });
});

// The guard is `Server.Timeline.append_event/4`'s clause for the three
// site-bound kinds, in Elixir — no Gleam code runs on this path.
test("rejects an on-site event with no site", {
  tag: ["@capability/technician-availability"],
}, async ({ request }) => {
  const technicianId = unique("tech");

  const response = await request.post(`/api/timeline/technicians/${technicianId}/events`, {
    headers: JSON_HEADERS,
    data: { kind: "arrived_on_site", occurred_at: 1_000 },
  });

  expect(response.status()).toBe(422);
  expect(await response.text()).toContain("requires site_id");
});

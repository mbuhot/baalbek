import {
  BASE_URL,
  USES_LOCAL_STACK,
  assertStackRunsImages,
  compose,
  requireStackImages,
  waitForHttp,
} from "./stack";

/** Brings the containerised stack — the release image and the PWA image — up before any test runs. */
export default async function globalSetup(): Promise<void> {
  if (!USES_LOCAL_STACK) {
    // E2E_BASE_URL names an environment this suite does not own: no image to
    // check, nothing to start, and nothing to tear down afterwards.
    await waitForHttp(`${BASE_URL}/api/json/core/customers`);
    process.stdout.write(`e2e running against ${BASE_URL} (E2E_BASE_URL; no local stack)\n`);
    return;
  }

  const imageIds = requireStackImages();

  compose(["down", "--volumes", "--remove-orphans", "--timeout", "5"]);
  compose(["up", "--detach", "--wait", "postgres"]);
  // Roles, schemas, migrations and the timeline tables, from inside the release.
  compose(["run", "--rm", "bootstrap"]);
  compose(["up", "--detach", "--wait", "server", "web"]);

  assertStackRunsImages(imageIds);
  await waitForHttp(`${BASE_URL}/api/json/core/customers`);

  const running = Object.entries(imageIds)
    .map(([service, id]) => `${service}=${id.slice(0, 19)}`)
    .join(" ");
  process.stdout.write(`e2e stack ready at ${BASE_URL} (${running})\n`);
}

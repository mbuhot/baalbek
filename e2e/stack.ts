import { execFileSync } from "node:child_process";

/** Control of the containerised stack in docker-compose.yml — the release image, its Postgres, and the PWA image. */

const composeFile = new URL("./docker-compose.yml", import.meta.url).pathname;
const projectDir = new URL("./", import.meta.url).pathname;

/** The images the stack must run, one per tier, matching `moon run server:image` and `moon run web:image`. */
export const STACK_IMAGES = {
  server: process.env.SERVER_IMAGE ?? "baalbek-server:latest",
  web: process.env.WEB_IMAGE ?? "baalbek-web:latest",
};

/** Origin the suite drives: the PWA image, serving the built bundle and proxying /api to the release. */
export const BASE_URL = process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_HOST_PORT ?? "4014"}`;

/** False when `E2E_BASE_URL` names an environment someone else runs; nothing here then starts or stops containers. */
export const USES_LOCAL_STACK = process.env.E2E_BASE_URL === undefined;

export function compose(args: string[], options: { quiet?: boolean } = {}): string {
  return execFileSync("docker", ["compose", "--file", composeFile, ...args], {
    cwd: projectDir,
    encoding: "utf8",
    stdio: options.quiet ? ["ignore", "pipe", "pipe"] : ["ignore", "pipe", "inherit"],
  });
}

/** Ids of the images the stack will run, failing when one is absent rather than letting compose pull something else. */
export function requireStackImages(): Record<string, string> {
  const ids: Record<string, string> = {};

  for (const [service, image] of Object.entries(STACK_IMAGES)) {
    try {
      ids[service] = execFileSync("docker", ["image", "inspect", "--format", "{{.Id}}", image], {
        encoding: "utf8",
      }).trim();
    } catch {
      // --force, because `moon run <id>:image` alone can be a cache hit: Moon hashes inputs, not the daemon's images.
      throw new Error(`${image} is not in the local docker daemon. Run \`moon run ${service}:image --force\`.`);
    }
  }

  return ids;
}

/**
 * Asserts each service runs the image id its own project built.
 *
 * The suite talks HTTP to a port, and a port can be served by anything. This is
 * what makes "the tests ran against the release image and the PWA image" a
 * checked fact rather than an assumption.
 */
export function assertStackRunsImages(expected: Record<string, string>): void {
  for (const [service, expectedId] of Object.entries(expected)) {
    const containerId = compose(["ps", "--quiet", service], { quiet: true }).trim();
    if (containerId === "") throw new Error(`no \`${service}\` container is running in the e2e stack`);

    const actual = execFileSync("docker", ["inspect", "--format", "{{.Image}}", containerId], {
      encoding: "utf8",
    }).trim();

    if (actual !== expectedId) {
      throw new Error(
        `the e2e stack's \`${service}\` container runs image ${actual}, not ${STACK_IMAGES[service as keyof typeof STACK_IMAGES]} (${expectedId})`,
      );
    }
  }
}

export async function waitForHttp(url: string, timeoutMs = 60_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  let lastError = "no attempt made";

  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) return;
      lastError = `HTTP ${response.status}`;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

  throw new Error(`${url} did not answer within ${timeoutMs}ms (last: ${lastError})`);
}

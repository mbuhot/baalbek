import { USES_LOCAL_STACK, compose } from "./stack";

/** Destroys the stack and its data after the run; set E2E_KEEP_STACK=1 to keep it for debugging. */
export default async function globalTeardown(): Promise<void> {
  if (!USES_LOCAL_STACK) return;

  if (process.env.E2E_KEEP_STACK === "1") {
    process.stdout.write("e2e stack left running (E2E_KEEP_STACK=1)\n");
    return;
  }

  compose(["down", "--volumes", "--remove-orphans", "--timeout", "5"]);
}

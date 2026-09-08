/** Regenerates `src/generated/model.json` from the moon graph, git history, `capabilities.yml`, and the e2e suite. */

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";
import { buildModel } from "./build-model.ts";
import { parseCapabilities, resolveClaims } from "./capabilities.ts";
import { parsePlaywrightList, specsByCapability, validateSpecClaims } from "./e2e-specs.ts";
import { GIT_LOG_FORMAT, parseGitLog } from "./git-stats.ts";
import type { RawGraph, RawProject, RawTask } from "./moon-graph.ts";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const workspaceRoot = resolve(projectRoot, "..");

const DEFAULT_HISTORY_LIMIT = 500;

function run(command: string, args: string[]): string {
  return execFileSync(command, args, {
    cwd: workspaceRoot,
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
  });
}

/**
 * Reads one JSON document from a command that may print an NDJSON notice line
 * first: moon does that when it activates a toolchain, and the notice is a
 * whole object on its own line, so leading lines that parse alone are dropped.
 */
function runJson<T>(command: string, args: string[]): T {
  const raw = run(command, args);
  try {
    return JSON.parse(raw) as T;
  } catch (error) {
    const lines = raw.split("\n");
    let start = 0;
    while (start < lines.length && parsesAlone(lines[start] ?? "")) start += 1;
    if (start === 0) throw error;
    return JSON.parse(lines.slice(start).join("\n")) as T;
  }
}

function parsesAlone(line: string): boolean {
  if (line.trim() === "") return true;
  try {
    return typeof JSON.parse(line) === "object";
  } catch {
    return false;
  }
}

/** `e2e:list`'s declared output. Playwright owns the spec parser; this reads what it wrote. */
const E2E_LIST = resolve(workspaceRoot, "e2e/build/test-list.json");

function fail(heading: string, problems: string[]): never {
  process.stderr.write(`${heading}\n${problems.map((p) => `  - ${p}`).join("\n")}\n`);
  process.exit(1);
}

const historyLimit = Number(process.env["EXPLORER_HISTORY_LIMIT"] ?? DEFAULT_HISTORY_LIMIT);

const projectGraph = runJson<RawGraph<RawProject>>("moon", ["project-graph", "--json"]);
const taskGraph = runJson<RawGraph<RawTask>>("moon", ["task-graph", "--json"]);
if (!existsSync(E2E_LIST)) {
  fail("the e2e test list is missing:", [`${E2E_LIST} — run \`moon run e2e:list\``]);
}
const playwrightList = JSON.parse(readFileSync(E2E_LIST, "utf8"));
const commits = parseGitLog(
  run("git", ["log", "--no-merges", `--format=${GIT_LOG_FORMAT}`, "--name-only", "-n", String(historyLimit)]),
);
const trackedFiles = run("git", ["ls-files"]).split("\n").filter((line) => line !== "");
const head = run("git", ["rev-parse", "HEAD"]).trim();

const { file: capabilityFile, errors: parseErrors } = parseCapabilities(
  parseYaml(readFileSync(resolve(projectRoot, "capabilities.yml"), "utf8")),
);
if (parseErrors.length > 0) fail("capabilities.yml is malformed:", parseErrors);

const rawProjects = Object.values(
  projectGraph.data as Record<string, { id: string; source: string; config?: { tags?: string[] } }>,
);
const projectClaims = rawProjects.map((project) => ({ id: project.id, tags: project.config?.tags ?? [] }));
const configFiles = rawProjects
  .map((project) => (project.source === "." ? "moon.yml" : `${project.source}/moon.yml`))
  .filter((path) => existsSync(resolve(workspaceRoot, path)));
const { claims, errors: claimErrors } = resolveClaims(capabilityFile, projectClaims);
if (claimErrors.length > 0) {
  fail("the capability vocabulary and the projects that claim it disagree:", claimErrors);
}

const defined = new Set(capabilityFile.capabilities.map((capability) => capability.id));
const e2eSpecs = parsePlaywrightList(playwrightList);
const specErrors = validateSpecClaims(e2eSpecs, defined);
if (specErrors.length > 0) fail("the e2e suite's capability tags do not match the vocabulary:", specErrors);

const model = buildModel({
  projectGraph,
  taskGraph,
  capabilityFile,
  claims,
  specsByCapability: specsByCapability(e2eSpecs, defined),
  commits,
  historyLimit,
  trackedFiles,
  configFiles,
  generatedAt: process.env["EXPLORER_GENERATED_AT"] ?? new Date().toISOString(),
  commit: head,
});

const target = resolve(projectRoot, "src/generated/model.json");
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, `${JSON.stringify(model, null, 2)}\n`);

const covered = model.capabilities.filter((capability) => capability.specs.length > 0).length;
process.stdout.write(
  `explorer: ${model.projects.length} projects, ${model.projectEdges.length} project edges, ` +
    `${model.taskEdges.length} task edges, ${model.capabilities.length} capabilities ` +
    `(${covered} with e2e coverage), ${model.history.commits} commits -> src/generated/model.json\n`,
);

/** Parses `capabilities.yml` (the vocabulary) and joins it to the claims projects make in their own `moon.yml`. */

export interface CapabilityEntry {
  id: string;
  name: string;
  description: string;
}

export interface PlatformEntry {
  id: string;
  reason: string;
}

export interface CapabilityFile {
  capabilities: CapabilityEntry[];
  platform: PlatformEntry[];
}

/** A project's claim, as moon reports it in `config.tags`. */
export interface ProjectClaim {
  id: string;
  tags: string[];
}

export interface ResolvedClaims {
  /** Capability id -> the projects that serve it, sorted. */
  componentsOf: Map<string, string[]>;
  /** Project id -> the capabilities it serves, in vocabulary order. */
  capabilitiesOf: Map<string, string[]>;
  platformReasons: Map<string, string>;
}

/** seed.md §9 keeps this input honest by keeping it small: a dozen capabilities, not hundreds. */
export const MAX_CAPABILITIES = 16;

/** Project tag naming a capability. Slashes are legal in a moon tag id; colons are not. */
export const CAPABILITY_TAG_PREFIX = "capability/";

/** Project tag standing in for "serves no business capability". */
export const PLATFORM_TAG = "platform";

function asRecord(value: unknown, where: string, errors: string[]): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    errors.push(`${where}: expected a mapping`);
    return null;
  }
  return value as Record<string, unknown>;
}

function asString(value: unknown, where: string, errors: string[]): string {
  if (typeof value !== "string" || value.trim() === "") {
    errors.push(`${where}: expected a non-empty string`);
    return "";
  }
  return value;
}

export function parseCapabilities(document: unknown): { file: CapabilityFile; errors: string[] } {
  const errors: string[] = [];
  const root = asRecord(document, "capabilities.yml", errors) ?? {};

  const capabilities: CapabilityEntry[] = [];
  const rawCapabilities = Array.isArray(root["capabilities"]) ? (root["capabilities"] as unknown[]) : [];
  if (!Array.isArray(root["capabilities"])) errors.push("capabilities.yml: `capabilities` must be a list");
  rawCapabilities.forEach((raw, index) => {
    const entry = asRecord(raw, `capabilities[${index}]`, errors);
    if (entry === null) return;
    // A leftover component list would otherwise be ignored in silence, which is the drift this split removes.
    if (entry["components"] !== undefined) {
      errors.push(
        `capabilities[${index}]: \`components\` no longer belongs here — a project claims a capability with the ` +
          `tag \`${CAPABILITY_TAG_PREFIX}<id>\` in its own moon.yml`,
      );
    }
    capabilities.push({
      id: asString(entry["id"], `capabilities[${index}].id`, errors),
      name: asString(entry["name"], `capabilities[${index}].name`, errors),
      description: asString(entry["description"], `capabilities[${index}].description`, errors),
    });
  });

  const platform: PlatformEntry[] = [];
  const rawPlatform = Array.isArray(root["platform"]) ? (root["platform"] as unknown[]) : [];
  if (!Array.isArray(root["platform"])) errors.push("capabilities.yml: `platform` must be a list");
  rawPlatform.forEach((raw, index) => {
    const entry = asRecord(raw, `platform[${index}]`, errors);
    if (entry === null) return;
    platform.push({
      id: asString(entry["id"], `platform[${index}].id`, errors),
      reason: asString(entry["reason"], `platform[${index}].reason`, errors),
    });
  });

  const seen = new Set<string>();
  for (const capability of capabilities) {
    if (seen.has(capability.id)) errors.push(`duplicate capability id: ${capability.id}`);
    seen.add(capability.id);
  }
  if (capabilities.length > MAX_CAPABILITIES) {
    errors.push(`${capabilities.length} capabilities declared, at most ${MAX_CAPABILITIES} allowed`);
  }

  return { file: { capabilities, platform }, errors };
}

/**
 * Joins the vocabulary to the claim each project makes in its own `moon.yml`.
 *
 * Every project must claim at least one defined capability, or tag itself
 * `platform` and give a reason in `capabilities.yml`. Anything else fails the
 * generator, so a component cannot arrive without saying what it is for.
 */
export function resolveClaims(
  file: CapabilityFile,
  projects: ProjectClaim[],
): { claims: ResolvedClaims; errors: string[] } {
  const errors: string[] = [];
  const defined = new Set(file.capabilities.map((capability) => capability.id));
  const order = new Map(file.capabilities.map((capability, index) => [capability.id, index]));

  const componentsOf = new Map<string, string[]>(file.capabilities.map((capability) => [capability.id, []]));
  const capabilitiesOf = new Map<string, string[]>();
  const platformReasons = new Map<string, string>();
  const taggedPlatform = new Set<string>();

  for (const project of [...projects].sort((a, b) => a.id.localeCompare(b.id))) {
    const claimed: string[] = [];
    let rejected = false;
    for (const tag of project.tags) {
      if (tag === PLATFORM_TAG) {
        taggedPlatform.add(project.id);
        continue;
      }
      if (!tag.startsWith(CAPABILITY_TAG_PREFIX)) continue;
      const id = tag.slice(CAPABILITY_TAG_PREFIX.length);
      if (!defined.has(id)) {
        errors.push(`project ${project.id} claims capability ${id}, which capabilities.yml does not define`);
        rejected = true;
        continue;
      }
      if (!claimed.includes(id)) claimed.push(id);
    }
    claimed.sort((a, b) => (order.get(a) ?? 0) - (order.get(b) ?? 0));

    if (taggedPlatform.has(project.id) && claimed.length > 0) {
      errors.push(`project ${project.id} is tagged ${PLATFORM_TAG} and also claims a capability`);
    }
    // A rejected tag already said what is wrong; "claims nothing" on top of it only obscures the typo.
    if (!taggedPlatform.has(project.id) && claimed.length === 0 && !rejected) {
      errors.push(
        `project ${project.id} claims no capability — tag it \`${CAPABILITY_TAG_PREFIX}<id>\` or \`${PLATFORM_TAG}\``,
      );
    }
    capabilitiesOf.set(project.id, claimed);
    for (const id of claimed) componentsOf.get(id)?.push(project.id);
  }

  const known = new Set(projects.map((project) => project.id));
  for (const entry of file.platform) {
    if (!known.has(entry.id)) {
      errors.push(`capabilities.yml: platform entry ${entry.id} names no project in the graph`);
      continue;
    }
    if (platformReasons.has(entry.id)) errors.push(`capabilities.yml: platform lists ${entry.id} twice`);
    if (!taggedPlatform.has(entry.id)) {
      errors.push(`capabilities.yml: platform entry ${entry.id} is not tagged ${PLATFORM_TAG} in its moon.yml`);
    }
    platformReasons.set(entry.id, entry.reason);
  }
  for (const id of taggedPlatform) {
    if (!platformReasons.has(id)) {
      errors.push(`project ${id} is tagged ${PLATFORM_TAG}, but capabilities.yml gives no reason`);
    }
  }

  for (const [id, components] of componentsOf) {
    if (components.length === 0) errors.push(`capability ${id} is claimed by no project`);
  }

  return { claims: { componentsOf, capabilitiesOf, platformReasons }, errors };
}

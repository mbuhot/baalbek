/** Reads the capability tags on the e2e suite from `playwright test --list --reporter=json`. */

export interface E2eSpec {
  /** `<file> › <title>`, the same shape Playwright's own reporters print. */
  id: string;
  file: string;
  title: string;
  capabilities: string[];
}

/** Playwright tag naming a capability, as written in a spec. `--grep` matches this spelling. */
export const CAPABILITY_TAG = "@capability/";

/** The JSON reporter strips the leading `@`, so match on what it actually emits. */
const REPORTED_PREFIX = "capability/";

function capabilityOf(tag: string): string | null {
  const bare = tag.startsWith("@") ? tag.slice(1) : tag;
  return bare.startsWith(REPORTED_PREFIX) ? bare.slice(REPORTED_PREFIX.length) : null;
}

interface RawSpec {
  title?: string;
  file?: string;
  tags?: string[];
}

interface RawSuite {
  file?: string;
  specs?: RawSpec[];
  suites?: RawSuite[];
}

function walk(suites: RawSuite[], into: E2eSpec[]): void {
  for (const suite of suites) {
    for (const spec of suite.specs ?? []) {
      const file = spec.file ?? suite.file ?? "";
      const title = spec.title ?? "";
      into.push({
        id: `${file} › ${title}`,
        file,
        title,
        capabilities: (spec.tags ?? []).map(capabilityOf).filter((id) => id !== null),
      });
    }
    walk(suite.suites ?? [], into);
  }
}

export function parsePlaywrightList(document: unknown): E2eSpec[] {
  const root = document as { suites?: RawSuite[] } | null;
  const specs: E2eSpec[] = [];
  walk(root?.suites ?? [], specs);
  return specs.sort((a, b) => a.id.localeCompare(b.id));
}

/**
 * Checks the suite's claims against the vocabulary, asymmetrically on purpose.
 *
 * A spec naming a capability the vocabulary does not define is a typo or an
 * un-propagated rename, and fails. A capability with no spec is reported as a
 * blind spot instead, because failing would only buy a hollow spec.
 */
export function validateSpecClaims(specs: E2eSpec[], defined: Set<string>): string[] {
  const errors: string[] = [];
  for (const spec of specs) {
    for (const id of spec.capabilities) {
      if (!defined.has(id)) {
        errors.push(`e2e spec "${spec.id}" is tagged ${CAPABILITY_TAG}${id}, which capabilities.yml does not define`);
      }
    }
    if (spec.capabilities.length === 0) {
      errors.push(`e2e spec "${spec.id}" claims no capability — tag it \`${CAPABILITY_TAG}<id>\``);
    }
  }
  return errors;
}

/** Capability id -> the specs that prove it, sorted. */
export function specsByCapability(specs: E2eSpec[], defined: Set<string>): Map<string, string[]> {
  const byCapability = new Map<string, string[]>([...defined].map((id) => [id, []]));
  for (const spec of specs) {
    for (const id of spec.capabilities) byCapability.get(id)?.push(spec.id);
  }
  for (const list of byCapability.values()) list.sort();
  return byCapability;
}

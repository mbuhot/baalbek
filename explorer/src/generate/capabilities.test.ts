import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";
import { describe, expect, it } from "vitest";
import { parseCapabilities, resolveClaims, MAX_CAPABILITIES } from "./capabilities.ts";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

function file(overrides: Partial<{ capabilities: unknown[]; platform: unknown[] }> = {}): unknown {
  return {
    capabilities: [{ id: "c1", name: "One", description: "A thing." }],
    platform: [{ id: "b", reason: "Tooling." }],
    ...overrides,
  };
}

const CLAIMS = [
  { id: "a", tags: ["capability/c1"] },
  { id: "b", tags: ["platform"] },
];

describe("parseCapabilities", () => {
  it("accepts a well-formed vocabulary", () => {
    const { file: parsed, errors } = parseCapabilities(file());
    expect(errors).toEqual([]);
    expect(parsed.capabilities[0]?.id).toBe("c1");
  });

  it("rejects a leftover component list, which the split moved into each moon.yml", () => {
    const { errors } = parseCapabilities(
      file({ capabilities: [{ id: "c1", name: "One", description: "x", components: ["a"] }] }),
    );
    expect(errors.some((e) => e.includes("`components` no longer belongs here"))).toBe(true);
  });

  it("rejects a duplicate capability id", () => {
    const one = { id: "c1", name: "One", description: "x" };
    const { errors } = parseCapabilities(file({ capabilities: [one, { ...one }] }));
    expect(errors).toContain("duplicate capability id: c1");
  });

  it("caps the list, because a capability per module is a worse project graph", () => {
    const many = Array.from({ length: MAX_CAPABILITIES + 1 }, (_, i) => ({
      id: `c${i}`,
      name: `C${i}`,
      description: "x",
    }));
    const { errors } = parseCapabilities(file({ capabilities: many }));
    expect(errors.some((e) => e.includes("at most"))).toBe(true);
  });
});

describe("resolveClaims", () => {
  const { file: parsed } = parseCapabilities(file());

  it("joins the vocabulary to the tags each project declares", () => {
    const { claims, errors } = resolveClaims(parsed, CLAIMS);
    expect(errors).toEqual([]);
    expect(claims.componentsOf.get("c1")).toEqual(["a"]);
    expect(claims.capabilitiesOf.get("a")).toEqual(["c1"]);
    expect(claims.platformReasons.get("b")).toBe("Tooling.");
  });

  it("fails for a project that claims a capability the vocabulary does not define", () => {
    const { errors } = resolveClaims(parsed, [...CLAIMS, { id: "c", tags: ["capability/typo"] }]);
    expect(errors).toContain("project c claims capability typo, which capabilities.yml does not define");
  });

  it("fails for a project that claims nothing", () => {
    const { errors } = resolveClaims(parsed, [...CLAIMS, { id: "c", tags: [] }]);
    expect(errors.some((e) => e.startsWith("project c claims no capability"))).toBe(true);
  });

  it("fails for a project that is both platform and a capability component", () => {
    const { errors } = resolveClaims(parsed, [{ id: "a", tags: ["capability/c1", "platform"] }]);
    expect(errors).toContain("project a is tagged platform and also claims a capability");
  });

  it("fails for a platform project with no stated reason", () => {
    const { errors } = resolveClaims(parsed, [...CLAIMS, { id: "c", tags: ["platform"] }]);
    expect(errors).toContain("project c is tagged platform, but capabilities.yml gives no reason");
  });

  it("fails for a platform reason whose project stopped being platform", () => {
    const { errors } = resolveClaims(parsed, [{ id: "a", tags: ["capability/c1"] }, { id: "b", tags: ["capability/c1"] }]);
    expect(errors).toContain("capabilities.yml: platform entry b is not tagged platform in its moon.yml");
  });

  it("fails for a capability no project claims", () => {
    const { errors } = resolveClaims(parsed, [{ id: "b", tags: ["platform"] }]);
    expect(errors).toContain("capability c1 is claimed by no project");
  });

  it("ignores tags that are not capability claims, since moon uses tags for task inheritance too", () => {
    const { errors } = resolveClaims(parsed, [{ id: "a", tags: ["frontend", "capability/c1"] }, CLAIMS[1]!]);
    expect(errors).toEqual([]);
  });
});

describe("the checked-in capabilities.yml", () => {
  const document = parseYaml(readFileSync(resolve(projectRoot, "capabilities.yml"), "utf8"));

  it("parses without error", () => {
    expect(parseCapabilities(document).errors).toEqual([]);
  });

  it("gives every capability a description, so the map reads to someone who is not an engineer", () => {
    const { file: parsed } = parseCapabilities(document);
    for (const capability of parsed.capabilities) {
      expect(capability.description.endsWith(".")).toBe(true);
    }
  });
});

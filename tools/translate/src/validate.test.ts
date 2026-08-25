import { describe, it, expect } from "vitest";
import { extractPlaceholders, validateTranslations } from "./validate.js";
import type { MergedEntry } from "./types.js";

function entry(key: string, value: string): MergedEntry {
  return { key, value };
}

describe("extractPlaceholders", () => {
  it("finds simple and double-brace placeholders", () => {
    expect(extractPlaceholders("Hi {name}, see {{link}}")).toEqual(
      new Set(["name", "link"])
    );
  });

  it("finds the argument name of an ICU plural", () => {
    expect(
      extractPlaceholders("{count, plural, one {# item} other {# items}}")
    ).toEqual(new Set(["count"]));
  });

  it("returns an empty set for plain text", () => {
    expect(extractPlaceholders("Submit")).toEqual(new Set());
  });

  it("ignores ICU branch braces like `one {# item}`", () => {
    // `#` is not an identifier, so branch bodies contribute nothing
    expect(extractPlaceholders("one {# item}")).toEqual(new Set());
  });
});

describe("validateTranslations", () => {
  const requested = [entry("greet", "Hello, {name}!")];

  it("accepts a translation that preserves the placeholders", () => {
    const { accepted, rejected } = validateTranslations(requested, {
      greet: "Bonjour, {name} !",
    });
    expect(accepted).toEqual({ greet: "Bonjour, {name} !" });
    expect(rejected).toEqual([]);
  });

  it("rejects a translated placeholder name", () => {
    const { accepted, rejected } = validateTranslations(requested, {
      greet: "Bonjour, {nom} !",
    });
    expect(accepted).toEqual({});
    expect(rejected).toHaveLength(1);
    expect(rejected[0].key).toBe("greet");
    expect(rejected[0].reason).toMatch(/placeholder/i);
  });

  it("rejects a dropped placeholder", () => {
    const { rejected } = validateTranslations(requested, {
      greet: "Bonjour !",
    });
    expect(rejected).toHaveLength(1);
  });

  it("rejects non-string and empty values", () => {
    const { accepted, rejected } = validateTranslations(
      [entry("a", "A"), entry("b", "B")],
      { a: { nested: "object" } as unknown as string, b: "   " }
    );
    expect(accepted).toEqual({});
    expect(rejected.map((r) => r.key).sort()).toEqual(["a", "b"]);
  });

  it("discards keys that were never requested", () => {
    const { accepted, rejected } = validateTranslations(requested, {
      greet: "Bonjour, {name} !",
      invented: "Surprise",
    });
    expect(accepted).toEqual({ greet: "Bonjour, {name} !" });
    // Unrequested keys are dropped silently, not reported as failures
    expect(rejected).toEqual([]);
  });

  it("allows a placeholder to repeat across ICU plural branches", () => {
    const icu = [
      entry("items", "{count, plural, one {{count} item} other {{count} items}}"),
    ];
    const { accepted, rejected } = validateTranslations(icu, {
      items: "{count, plural, one {{count} objet} other {{count} objets}}",
    });
    expect(rejected).toEqual([]);
    expect(Object.keys(accepted)).toEqual(["items"]);
  });
});

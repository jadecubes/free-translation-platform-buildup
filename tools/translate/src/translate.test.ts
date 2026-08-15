import { describe, it, expect, vi, beforeEach } from "vitest";
import { mkdtempSync, writeFileSync, readFileSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { parseSourceMap, hashSourceValue, HASH_MANIFEST_FILE } from "./translate.js";
import type { SourceMap } from "./types.js";

// Shared mock translate function — tests can override per-test via mockResolvedValue
const mockTranslateFn = vi.fn().mockResolvedValue({
  submit: "Soumettre",
  welcomeUser: "Bienvenue, {name} !",
});

// Mock the gemini module so translate() never calls the real API
vi.mock("./gemini.js", () => {
  return {
    buildPrompt: vi.fn(),
    parseResponse: vi.fn(),
    GeminiTranslator: class MockGeminiTranslator {
      translate = mockTranslateFn;
    },
  };
});

// Import translate after mock is set up
const { translate } = await import("./translate.js");

function createTempDir(): string {
  return mkdtempSync(join(tmpdir(), "translate-test-"));
}

function writeJson(dir: string, filename: string, data: unknown): string {
  const filePath = join(dir, filename);
  writeFileSync(filePath, JSON.stringify(data, null, 2) + "\n", "utf-8");
  return filePath;
}

function readJson(filePath: string): Record<string, string> {
  return JSON.parse(readFileSync(filePath, "utf-8"));
}

// --- parseSourceMap tests ---

describe("parseSourceMap", () => {
  it("parses entries with value and context", () => {
    const source: SourceMap = {
      submit: { value: "Submit", context: "Button on forms" },
      cancel: { value: "Cancel", context: "Close dialog" },
    };
    const { entries, missingContextKeys } = parseSourceMap(source);
    expect(entries).toHaveLength(2);
    expect(entries[0]).toEqual({
      key: "submit",
      value: "Submit",
      context: "Button on forms",
    });
    expect(missingContextKeys).toHaveLength(0);
  });

  it("detects keys with missing context", () => {
    const source: SourceMap = {
      ok: { value: "OK" },
      submit: { value: "Submit", context: "Button" },
    };
    const { entries, missingContextKeys } = parseSourceMap(source);
    expect(entries).toHaveLength(2);
    expect(missingContextKeys).toEqual(["ok"]);
  });

  it("handles empty source map", () => {
    const { entries, missingContextKeys } = parseSourceMap({});
    expect(entries).toHaveLength(0);
    expect(missingContextKeys).toHaveLength(0);
  });
});

// --- translate() tests ---

describe("translate", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("translates all keys when no existing file", async () => {
    const dir = createTempDir();
    const sourceFile = writeJson(dir, "en-US.json", {
      submit: { value: "Submit", context: "Button" },
      welcomeUser: { value: "Welcome, {name}!", context: "Greeting" },
    });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: "fake-key",
    });

    expect(results).toHaveLength(1);
    expect(results[0].success).toBe(true);
    expect(results[0].newKeys).toBe(2);
    expect(results[0].existingKeys).toBe(0);

    // Verify output file was written
    const output = readJson(join(dir, "fr.json"));
    expect(output.submit).toBe("Soumettre");
    expect(output.welcomeUser).toBe("Bienvenue, {name} !");
  });

  it("only translates new keys when existing file has some", async () => {
    const dir = createTempDir();
    const sourceFile = writeJson(dir, "en-US.json", {
      submit: { value: "Submit", context: "Button" },
      welcomeUser: { value: "Welcome, {name}!", context: "Greeting" },
    });
    // Existing translation already has "submit"
    writeJson(dir, "fr.json", { submit: "Envoyer" });

    // Mock returns only the new key
    mockTranslateFn.mockResolvedValueOnce({
      welcomeUser: "Bienvenue, {name} !",
    });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: "fake-key",
    });

    expect(results[0].newKeys).toBe(1);
    expect(results[0].existingKeys).toBe(1);

    // Verify mock was called with only the new entry
    expect(mockTranslateFn).toHaveBeenCalledOnce();
    const entries = mockTranslateFn.mock.calls[0][0];
    expect(entries).toHaveLength(1);
    expect(entries[0].key).toBe("welcomeUser");

    // Verify merged output keeps existing + adds new
    const output = readJson(join(dir, "fr.json"));
    expect(output.submit).toBe("Envoyer"); // kept from existing
    expect(output.welcomeUser).toBe("Bienvenue, {name} !"); // from Gemini
  });

  it("skips language when all keys already translated", async () => {
    const dir = createTempDir();
    const sourceFile = writeJson(dir, "en-US.json", {
      submit: { value: "Submit", context: "Button" },
    });
    writeJson(dir, "fr.json", { submit: "Soumettre" });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: "fake-key",
    });

    expect(results[0].success).toBe(true);
    expect(results[0].newKeys).toBe(0);
    expect(mockTranslateFn).not.toHaveBeenCalled();
  });

  it("removes stale keys not in source", async () => {
    const dir = createTempDir();
    const sourceFile = writeJson(dir, "en-US.json", {
      submit: { value: "Submit", context: "Button" },
    });
    // Existing file has a key that's been removed from source
    writeJson(dir, "fr.json", {
      submit: "Soumettre",
      deletedKey: "Vieille traduction",
    });

    await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: "fake-key",
    });

    const output = readJson(join(dir, "fr.json"));
    expect(output.submit).toBe("Soumettre");
    expect(output).not.toHaveProperty("deletedKey");
  });

  it("re-translates keys whose source value changed", async () => {
    const dir = createTempDir();
    const sourceFile = writeJson(dir, "en-US.json", {
      submit: { value: "Save changes", context: "Button" },
    });
    // Existing translation was made from the old value "Submit"
    writeJson(dir, "fr.json", { submit: "Soumettre" });
    writeJson(dir, HASH_MANIFEST_FILE, {
      fr: { submit: hashSourceValue("Submit") },
    });

    mockTranslateFn.mockResolvedValueOnce({
      submit: "Enregistrer les modifications",
    });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: "fake-key",
    });

    expect(results[0].newKeys).toBe(1);
    expect(mockTranslateFn).toHaveBeenCalledOnce();
    expect(mockTranslateFn.mock.calls[0][0][0].key).toBe("submit");

    const output = readJson(join(dir, "fr.json"));
    expect(output.submit).toBe("Enregistrer les modifications");

    // Manifest now records the hash of the new source value
    const manifest = readJson(join(dir, HASH_MANIFEST_FILE)) as unknown as {
      fr: Record<string, string>;
    };
    expect(manifest.fr.submit).toBe(hashSourceValue("Save changes"));
  });

  it("trusts existing translations without manifest and backfills hashes", async () => {
    const dir = createTempDir();
    const sourceFile = writeJson(dir, "en-US.json", {
      submit: { value: "Submit", context: "Button" },
    });
    // Pre-manifest translation file: no hash record exists
    writeJson(dir, "fr.json", { submit: "Soumettre" });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: "fake-key",
    });

    expect(results[0].newKeys).toBe(0);
    expect(mockTranslateFn).not.toHaveBeenCalled();

    const manifest = readJson(join(dir, HASH_MANIFEST_FILE)) as unknown as {
      fr: Record<string, string>;
    };
    expect(manifest.fr.submit).toBe(hashSourceValue("Submit"));
  });

  it("handles multiple target languages", async () => {
    const dir = createTempDir();
    const sourceFile = writeJson(dir, "en-US.json", {
      submit: { value: "Submit", context: "Button" },
    });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr", "ja"],
      geminiApiKey: "fake-key",
    });

    expect(results).toHaveLength(2);
    expect(existsSync(join(dir, "fr.json"))).toBe(true);
    expect(existsSync(join(dir, "ja.json"))).toBe(true);
  });
});

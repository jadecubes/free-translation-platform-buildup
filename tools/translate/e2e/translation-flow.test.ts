/**
 * E2E test: proves the full Gemini translation pipeline works.
 *
 * This imports and runs the ACTUAL translate() function —
 * the same code path that GitLab CI uses. It verifies:
 *
 * 1. translate() can call the real Gemini API and get valid JSON back
 * 2. Output files are written correctly
 * 3. Placeholders ({name}) survive translation
 * 4. ICU plural format survives translation
 * 5. Differential translation works (only new keys are sent to Gemini)
 * 6. Stale keys are removed from output
 *
 * Requires GEMINI_API_KEY environment variable.
 * Run: cd tools/translate && GEMINI_API_KEY=your_key npx vitest run e2e
 */
import { describe, it, expect } from "vitest";
import { mkdtempSync, writeFileSync, readFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { translate } from "../src/translate.js";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

function setupTestDir(
  source: Record<string, { value: string; context?: string }>,
  existing?: Record<string, Record<string, string>>
): { dir: string; sourceFile: string } {
  const dir = mkdtempSync(join(tmpdir(), "e2e-translate-"));
  const sourceFile = join(dir, "en-US.json");
  writeFileSync(sourceFile, JSON.stringify(source, null, 2) + "\n");

  if (existing) {
    for (const [lang, translations] of Object.entries(existing)) {
      writeFileSync(
        join(dir, `${lang}.json`),
        JSON.stringify(translations, null, 2) + "\n"
      );
    }
  }

  return { dir, sourceFile };
}

function readOutputFile(dir: string, lang: string): Record<string, string> {
  return JSON.parse(readFileSync(join(dir, `${lang}.json`), "utf-8"));
}

describe.skipIf(!GEMINI_API_KEY)("Translation Flow (end-to-end with real Gemini API)", () => {
  it("translates all keys from source file to French", async () => {
    const { dir, sourceFile } = setupTestDir({
      submit: { value: "Submit", context: "Primary action button on forms" },
    });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: GEMINI_API_KEY!,
    });

    expect(results).toHaveLength(1);
    expect(results[0].success).toBe(true);
    expect(results[0].language).toBe("fr");
    expect(results[0].translatedKeys).toBe(1);
    expect(results[0].skippedKeys).toBe(0);

    const output = readOutputFile(dir, "fr");
    expect(output).toHaveProperty("submit");
    expect(typeof output.submit).toBe("string");
    expect(output.submit.length).toBeGreaterThan(0);
  });

  it("preserves {name} placeholder through translation", async () => {
    const { dir, sourceFile } = setupTestDir({
      welcomeUser: {
        value: "Welcome, {name}!",
        context:
          "Personalized greeting after login. {name} is a placeholder that must be preserved exactly",
      },
    });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: GEMINI_API_KEY!,
    });

    expect(results[0].success).toBe(true);

    const output = readOutputFile(dir, "fr");
    expect(output.welcomeUser).toContain("{name}");
  });

  it("preserves ICU plural format through translation", async () => {
    const { dir, sourceFile } = setupTestDir({
      itemCountPlural: {
        value: "{count, plural, one {# item} other {# items}}",
        context: "Pluralized item count using ICU format",
      },
    });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: GEMINI_API_KEY!,
    });

    expect(results[0].success).toBe(true);

    const output = readOutputFile(dir, "fr");
    expect(output.itemCountPlural).toContain("{count, plural,");
    expect(output.itemCountPlural).toContain("one {");
    expect(output.itemCountPlural).toContain("other {");
  });

  it("only translates new keys (differential translation)", async () => {
    const { dir, sourceFile } = setupTestDir(
      {
        submit: {
          value: "Submit",
          context: "Primary action button on forms",
        },
        cancel: {
          value: "Cancel",
          context: "Button to close dialogs without saving",
        },
      },
      {
        fr: { submit: "Envoyer" },
      }
    );

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: GEMINI_API_KEY!,
    });

    expect(results[0].success).toBe(true);
    expect(results[0].translatedKeys).toBe(1);
    expect(results[0].skippedKeys).toBe(1);

    const output = readOutputFile(dir, "fr");
    expect(output.submit).toBe("Envoyer");
    expect(output).toHaveProperty("cancel");
    expect(typeof output.cancel).toBe("string");
    expect(output.cancel.length).toBeGreaterThan(0);
  });

  it("removes stale keys no longer in source", async () => {
    const { dir, sourceFile } = setupTestDir(
      {
        submit: {
          value: "Submit",
          context: "Primary action button on forms",
        },
      },
      {
        fr: { submit: "Envoyer", oldFeature: "Ancienne fonctionnalité" },
      }
    );

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: GEMINI_API_KEY!,
    });

    expect(results[0].success).toBe(true);

    const output = readOutputFile(dir, "fr");
    expect(output).toHaveProperty("submit");
    expect(output).not.toHaveProperty("oldFeature");
  });

  it("translates to multiple languages in one call", async () => {
    const { dir, sourceFile } = setupTestDir({
      submit: { value: "Submit", context: "Primary action button on forms" },
    });

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr", "ja"],
      geminiApiKey: GEMINI_API_KEY!,
    });

    expect(results).toHaveLength(2);
    expect(results[0].success).toBe(true);
    expect(results[1].success).toBe(true);

    const fr = readOutputFile(dir, "fr");
    expect(fr).toHaveProperty("submit");

    const ja = readOutputFile(dir, "ja");
    expect(ja).toHaveProperty("submit");
    expect(ja.submit).toMatch(/[^\x00-\x7F]/);
  });
});

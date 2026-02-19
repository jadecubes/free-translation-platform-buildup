import { describe, it, expect } from "vitest";
import { mkdtempSync, writeFileSync, readFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { translate } from "../translate.js";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

describe.skipIf(!GEMINI_API_KEY)("integration: Gemini API", () => {
  it("translates a simple key to French", async () => {
    const dir = mkdtempSync(join(tmpdir(), "integration-test-"));
    const sourceFile = join(dir, "en-US.json");
    writeFileSync(
      sourceFile,
      JSON.stringify({
        submit: {
          value: "Submit",
          context: "Primary action button on forms",
        },
      }) + "\n"
    );

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: GEMINI_API_KEY!,
    });

    expect(results).toHaveLength(1);
    expect(results[0].success).toBe(true);
    expect(results[0].newKeys).toBe(1);

    const output = JSON.parse(readFileSync(join(dir, "fr.json"), "utf-8"));
    expect(output).toHaveProperty("submit");
    expect(typeof output.submit).toBe("string");
    expect(output.submit.length).toBeGreaterThan(0);
  }, 30000);

  it("preserves placeholders in translation", async () => {
    const dir = mkdtempSync(join(tmpdir(), "integration-test-"));
    const sourceFile = join(dir, "en-US.json");
    writeFileSync(
      sourceFile,
      JSON.stringify({
        welcomeUser: {
          value: "Welcome, {name}!",
          context: "Personalized greeting. {name} is a placeholder",
        },
      }) + "\n"
    );

    const results = await translate({
      sourceFile,
      outputDir: dir,
      targetLanguages: ["fr"],
      geminiApiKey: GEMINI_API_KEY!,
    });

    expect(results[0].success).toBe(true);

    const output = JSON.parse(readFileSync(join(dir, "fr.json"), "utf-8"));
    expect(output.welcomeUser).toContain("{name}");
  }, 30000);
});

import { resolve } from "path";
import { translate } from "./translate.js";

async function main() {
  // Configuration from environment variables
  const geminiApiKey = process.env.GEMINI_API_KEY;
  if (!geminiApiKey) {
    console.error("Error: GEMINI_API_KEY environment variable is required");
    process.exit(1);
  }

  const targetLanguagesEnv = process.env.TARGET_LANGUAGES || "fr,ja,zh-Hant-HK";
  const targetLanguages = targetLanguagesEnv.split(",").map((l) => l.trim());

  // Paths relative to project root (assumes CI runs from repo root)
  const projectRoot = process.env.PROJECT_ROOT || process.cwd();
  const localesDir = resolve(projectRoot, "locales");

  const sourceFile = resolve(localesDir, "en-US.json");
  const contextFile = resolve(localesDir, "en-US.context.json");

  console.log("=== Gemini Translation Tool ===\n");
  console.log(`Source file: ${sourceFile}`);
  console.log(`Context file: ${contextFile}`);
  console.log(`Target languages: ${targetLanguages.join(", ")}`);
  console.log(`Output directory: ${localesDir}\n`);

  try {
    const results = await translate({
      sourceFile,
      contextFile,
      outputDir: localesDir,
      targetLanguages,
      geminiApiKey,
    });

    // Summary
    console.log("\n=== Translation Summary ===");
    const successful = results.filter((r) => r.success);
    const failed = results.filter((r) => !r.success);

    console.log(`Successful: ${successful.length}/${results.length}`);
    for (const r of successful) {
      if (r.totalKeys !== undefined) {
        console.log(`  ${r.language}: ${r.newKeys} new, ${r.existingKeys} existing (${r.totalKeys} total)`);
      }
    }
    if (failed.length > 0) {
      console.log("Failed languages:");
      failed.forEach((r) => console.log(`  - ${r.language}: ${r.error}`));
      process.exit(1);
    }

    console.log("\nTranslation completed successfully!");
  } catch (error) {
    console.error("Translation failed:", error);
    process.exit(1);
  }
}

main();

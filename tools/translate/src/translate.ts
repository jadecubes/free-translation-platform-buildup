import { readFileSync, writeFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { GeminiTranslator } from "./gemini.js";
import type {
  TranslationMap,
  ContextMap,
  MergedEntry,
  TranslateOptions,
  TranslationResult,
} from "./types.js";

export async function translate(
  options: TranslateOptions
): Promise<TranslationResult[]> {
  const { sourceFile, contextFile, outputDir, targetLanguages, geminiApiKey } =
    options;

  // Read source translation map
  console.log(`Reading source file: ${sourceFile}`);
  const sourceMap = readJsonFile<TranslationMap>(sourceFile);

  // Read context file (optional)
  let contextMap: ContextMap = {};
  if (existsSync(contextFile)) {
    console.log(`Reading context file: ${contextFile}`);
    contextMap = readJsonFile<ContextMap>(contextFile);
  } else {
    console.warn(`Context file not found: ${contextFile}`);
    console.warn("Translations will proceed without context (less accurate)");
  }

  // Merge and detect missing contexts
  const { entries, missingContextKeys } = mergeSourceAndContext(
    sourceMap,
    contextMap
  );

  if (missingContextKeys.length > 0) {
    console.warn("\n--- Missing Context Warning ---");
    console.warn(
      `The following ${missingContextKeys.length} keys have no context:`
    );
    missingContextKeys.forEach((key) => console.warn(`  - ${key}`));
    console.warn(
      "Add context to en-US.context.json for better translation quality.\n"
    );
  }

  // Initialize Gemini translator
  const translator = new GeminiTranslator(geminiApiKey);

  // Translate to each target language
  const results: TranslationResult[] = [];

  for (const language of targetLanguages) {
    console.log(`\nTranslating to ${language}...`);

    try {
      const translations = await translator.translate(entries, language);

      // Write output file
      const outputFile = join(outputDir, `${language}.json`);
      writeJsonFile(outputFile, translations);
      console.log(`  Saved: ${outputFile}`);

      results.push({
        language,
        translations,
        success: true,
      });
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      console.error(`  Failed to translate to ${language}: ${errorMessage}`);

      results.push({
        language,
        translations: {},
        success: false,
        error: errorMessage,
      });
    }
  }

  return results;
}

function readJsonFile<T>(filePath: string): T {
  const content = readFileSync(filePath, "utf-8");
  return JSON.parse(content);
}

function writeJsonFile(filePath: string, data: unknown): void {
  writeFileSync(filePath, JSON.stringify(data, null, 2) + "\n", "utf-8");
}

function mergeSourceAndContext(
  sourceMap: TranslationMap,
  contextMap: ContextMap
): { entries: MergedEntry[]; missingContextKeys: string[] } {
  const entries: MergedEntry[] = [];
  const missingContextKeys: string[] = [];

  for (const [key, value] of Object.entries(sourceMap)) {
    const context = contextMap[key];

    if (!context) {
      missingContextKeys.push(key);
    }

    entries.push({
      key,
      value,
      context,
    });
  }

  return { entries, missingContextKeys };
}

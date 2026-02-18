import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
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
      // Read existing translations for this language
      const outputFile = join(outputDir, `${language}.json`);
      let existingMap: TranslationMap = {};
      if (existsSync(outputFile)) {
        existingMap = readJsonFile<TranslationMap>(outputFile);
        console.log(`  Found existing translations: ${Object.keys(existingMap).length} keys`);
      }

      // Find keys that are new (not in existing translations)
      const newEntries = entries.filter((e) => !(e.key in existingMap));

      const totalKeys = entries.length;
      const existingKeys = totalKeys - newEntries.length;
      const newKeyCount = newEntries.length;

      if (newEntries.length === 0) {
        console.log(`  No untranslated keys — skipping ${language}`);
        results.push({
          language,
          translations: existingMap,
          success: true,
          totalKeys,
          newKeys: 0,
          existingKeys,
        });
        continue;
      }

      console.log(`  Translating ${newEntries.length} new key(s) (${existingKeys} existing kept)...`);
      const newTranslations = await translator.translate(newEntries, language);

      // Merge: existing translations + new translations (new overrides if overlap)
      const mergedMap: TranslationMap = { ...existingMap, ...newTranslations };

      // Remove keys that no longer exist in source
      for (const key of Object.keys(mergedMap)) {
        if (!(key in sourceMap)) {
          delete mergedMap[key];
        }
      }

      writeJsonFile(outputFile, mergedMap);
      console.log(`  Saved: ${outputFile}`);

      results.push({
        language,
        translations: mergedMap,
        success: true,
        totalKeys,
        newKeys: newKeyCount,
        existingKeys,
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

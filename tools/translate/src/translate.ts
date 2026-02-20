import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { GeminiTranslator } from "./gemini.js";
import type {
  SourceMap,
  TranslationMap,
  MergedEntry,
  TranslateOptions,
  TranslationResult,
} from "./types.js";

export async function translate(
  options: TranslateOptions
): Promise<TranslationResult[]> {
  const { sourceFile, outputDir, targetLanguages, geminiApiKey } = options;

  // Read source file (combined value + context per key)
  console.log(`Reading source file: ${sourceFile}`);
  const sourceMap = readJsonFile<SourceMap>(sourceFile);

  // Parse entries and detect missing contexts
  const { entries, missingContextKeys } = parseSourceMap(sourceMap);

  if (missingContextKeys.length > 0) {
    console.warn("\n--- Missing Context Warning ---");
    console.warn(
      `The following ${missingContextKeys.length} keys have no context:`
    );
    missingContextKeys.forEach((key) => console.warn(`  - ${key}`));
    console.warn(
      "Add context to your i18n annotations for better translation quality.\n"
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

      let mergedMap: TranslationMap;

      if (newEntries.length === 0) {
        console.log(`  No untranslated keys — skipping translation for ${language}`);
        mergedMap = { ...existingMap };
      } else {
        console.log(`  Translating ${newEntries.length} new key(s) (${existingKeys} existing kept)...`);
        const newTranslations = await translator.translate(newEntries, language);

        // Merge: existing translations + new translations (new overrides if overlap)
        mergedMap = { ...existingMap, ...newTranslations };
      }

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

export function parseSourceMap(
  sourceMap: SourceMap
): { entries: MergedEntry[]; missingContextKeys: string[] } {
  const entries: MergedEntry[] = [];
  const missingContextKeys: string[] = [];

  for (const [key, entry] of Object.entries(sourceMap)) {
    if (!entry.context) {
      missingContextKeys.push(key);
    }

    entries.push({
      key,
      value: entry.value,
      context: entry.context,
    });
  }

  return { entries, missingContextKeys };
}

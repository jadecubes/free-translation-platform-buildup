import { readFileSync, writeFileSync, existsSync } from "fs";
import { createHash } from "crypto";
import { join } from "path";
import { GeminiTranslator } from "./gemini.js";
import type {
  SourceMap,
  TranslationMap,
  MergedEntry,
  HashManifest,
  TranslateOptions,
  TranslationResult,
} from "./types.js";

export const HASH_MANIFEST_FILE = ".translation-hashes.json";

export function hashSourceValue(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 12);
}

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

  const manifestFile = join(outputDir, HASH_MANIFEST_FILE);
  const manifest: HashManifest = existsSync(manifestFile)
    ? readJsonFile<HashManifest>(manifestFile)
    : {};

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

      const langHashes = manifest[language] ?? {};

      // New key, or source value changed since last translation; a key with no
      // manifest record (files predating the manifest) is trusted and backfilled
      const entriesToTranslate = entries.filter((entry) => {
        if (!(entry.key in existingMap)) return true;
        const lastHash = langHashes[entry.key];
        return lastHash !== undefined && lastHash !== hashSourceValue(entry.value);
      });

      const totalKeys = entries.length;
      const existingKeys = totalKeys - entriesToTranslate.length;
      const newKeyCount = entriesToTranslate.length;

      let mergedMap: TranslationMap;

      if (entriesToTranslate.length === 0) {
        console.log(`  No new or changed keys — skipping translation for ${language}`);
        mergedMap = { ...existingMap };
      } else {
        console.log(`  Translating ${entriesToTranslate.length} new/updated key(s) (${existingKeys} existing kept)...`);
        const newTranslations = await translator.translate(entriesToTranslate, language);

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

      manifest[language] = Object.fromEntries(
        Object.keys(mergedMap).map((key) => [key, hashSourceValue(sourceMap[key].value)])
      );

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

  writeJsonFile(manifestFile, manifest);

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

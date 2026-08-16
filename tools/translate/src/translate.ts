import { readFileSync, writeFileSync, existsSync } from "fs";
import { createHash } from "crypto";
import { join } from "path";
import { GeminiTranslator, normalizeEntry } from "./gemini.js";
import type {
  SourceMap,
  TranslationMap,
  MergedEntry,
  HashManifest,
  TranslateOptions,
  TranslationResult,
} from "./types.js";

export const HASH_MANIFEST_FILE = ".translation-hashes.json";

/**
 * Hash of what the translator is given for a key — value and context, sharing
 * the prompt's own normalization. An edit that changes either re-translates;
 * one that changes neither (adding an empty context) does not.
 */
export function hashSourceEntry(entry: MergedEntry): string {
  const { value, context } = normalizeEntry(entry);
  return createHash("sha256")
    .update(JSON.stringify([value, context ?? null]))
    .digest("hex")
    .slice(0, 12);
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
  const manifest = readJsonFileIfExists<HashManifest>(manifestFile, {});

  // Source hashes are language-independent — compute once, not per language
  const sourceHashes: HashManifest[string] = Object.fromEntries(
    entries.map((entry) => [entry.key, hashSourceEntry(entry)])
  );

  // Initialize Gemini translator
  const translator = new GeminiTranslator(geminiApiKey);

  // Translate to each target language
  const results: TranslationResult[] = [];

  for (const language of targetLanguages) {
    console.log(`\nTranslating to ${language}...`);

    try {
      // Read existing translations for this language
      const outputFile = join(outputDir, `${language}.json`);
      const existingMap = readJsonFileIfExists<TranslationMap>(outputFile, {});
      const existingCount = Object.keys(existingMap).length;
      if (existingCount > 0) {
        console.log(`  Found existing translations: ${existingCount} keys`);
      }

      // Hashes this language was last translated from. An already-translated key
      // with no record predates the manifest: trust it and backfill from the
      // current source, so the rest of the run has one hash per translated key.
      const langHashes: HashManifest[string] = { ...(manifest[language] ?? {}) };
      const backfilledKeys = Object.keys(existingMap).filter(
        (key) => !(key in langHashes) && key in sourceHashes
      );
      for (const key of backfilledKeys) {
        langHashes[key] = sourceHashes[key];
      }
      if (backfilledKeys.length > 0) {
        console.log(
          `  No hash record for ${backfilledKeys.length} existing key(s) — trusting them and backfilling`
        );
      }

      // New key, or source value changed since it was last translated
      const entriesToTranslate = entries.filter(
        (entry) =>
          !(entry.key in existingMap) ||
          langHashes[entry.key] !== sourceHashes[entry.key]
      );

      const totalKeys = entries.length;
      const requestedKeys = entriesToTranslate.length;

      let newTranslations: TranslationMap = {};
      if (requestedKeys === 0) {
        console.log(`  No new or changed keys — skipping translation for ${language}`);
      } else {
        console.log(`  Translating ${requestedKeys} new/updated key(s) (${totalKeys - requestedKeys} unchanged kept)...`);
        newTranslations = await translator.translate(entriesToTranslate, language);
      }

      // Report what the translator actually returned, which is what the manifest
      // records too — a requested key it dropped is not translated
      const droppedKeys = entriesToTranslate
        .filter((entry) => !(entry.key in newTranslations))
        .map((entry) => entry.key);
      const translatedKeys = requestedKeys - droppedKeys.length;

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

      // Record what each key was actually translated from: keys the translator
      // just returned get the current source hash, anything else keeps its prior
      // hash — so a key the translator failed to return stays flagged as stale
      // and is retried next run instead of being marked up to date
      manifest[language] = Object.fromEntries(
        Object.keys(mergedMap).map((key) => [
          key,
          key in newTranslations ? sourceHashes[key] : langHashes[key],
        ])
      );

      results.push({
        language,
        translations: mergedMap,
        success: true,
        totalKeys,
        requestedKeys,
        translatedKeys,
        droppedKeys,
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

function readJsonFileIfExists<T>(filePath: string, fallback: T): T {
  return existsSync(filePath) ? readJsonFile<T>(filePath) : fallback;
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

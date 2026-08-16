export interface SourceEntry {
  value: string;
  context?: string;
}

export interface SourceMap {
  [key: string]: SourceEntry;
}

export interface TranslationMap {
  [key: string]: string;
}

/** Per-language record of the source hash (value + context) each key was last translated from */
export interface HashManifest {
  [language: string]: { [key: string]: string };
}

export interface MergedEntry {
  key: string;
  value: string;
  context?: string;
}

export interface TranslateOptions {
  sourceFile: string;
  outputDir: string;
  targetLanguages: string[];
  geminiApiKey: string;
}

export interface TranslationResult {
  language: string;
  translations: TranslationMap;
  success: boolean;
  error?: string;
  totalKeys?: number;
  /** Keys sent to the translator this run (new key, or source changed) */
  requestedKeys?: number;
  /** Keys the translator returned a value for; below requestedKeys if it dropped some */
  translatedKeys?: number;
  /** Keys kept as-is (already translated from an unchanged source) */
  skippedKeys?: number;
}

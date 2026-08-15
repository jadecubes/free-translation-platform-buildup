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

/** Per-language record of the source-value hash each key was last translated from */
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
  newKeys?: number;
  existingKeys?: number;
}

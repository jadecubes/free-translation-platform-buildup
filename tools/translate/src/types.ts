export interface TranslationMap {
  [key: string]: string;
}

export interface ContextMap {
  [key: string]: string;
}

export interface MergedEntry {
  key: string;
  value: string;
  context?: string;
}

export interface TranslateOptions {
  sourceFile: string;
  contextFile: string;
  outputDir: string;
  targetLanguages: string[];
  geminiApiKey: string;
}

export interface TranslationResult {
  language: string;
  translations: TranslationMap;
  success: boolean;
  error?: string;
}

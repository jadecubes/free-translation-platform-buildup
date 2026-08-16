import { GoogleGenerativeAI } from "@google/generative-ai";
import type { MergedEntry, TranslationMap } from "./types.js";

/**
 * The entry as the translator effectively sees it: an empty context is no
 * context. Both the prompt and the hash manifest go through here, so the two
 * agree on what counts as a change without the manifest being pinned to the
 * prompt's wording — retouching the template below must not re-translate
 * the whole corpus.
 */
export function normalizeEntry(entry: MergedEntry): MergedEntry {
  return {
    key: entry.key,
    value: entry.value,
    context: entry.context || undefined,
  };
}

/** The block describing one key in the prompt. */
export function describeEntry(entry: MergedEntry): string {
  const { key, value, context } = normalizeEntry(entry);
  const contextPart = context ? `\n   Context: ${context}` : "";
  return `- Key: "${key}"\n   Value: "${value}"${contextPart}`;
}

export function buildPrompt(
  entries: MergedEntry[],
  targetLanguage: string
): string {
  const entriesDescription = entries.map(describeEntry).join("\n\n");

  return `You are a professional translator. Translate the following UI strings from English to ${targetLanguage}.

IMPORTANT RULES:
1. Preserve all placeholders exactly as they appear (e.g., {count}, {name}, {{variable}})
2. Use the context provided to choose the most appropriate translation
3. Maintain consistent terminology across all translations
4. Use the appropriate level of formality for the target language
5. Return ONLY a valid JSON object with the same keys and translated values
6. Do not include any markdown formatting, code blocks, or explanations

Strings to translate:

${entriesDescription}

Return a JSON object where each key maps to its translated value. Example format:
{"key1": "translated value 1", "key2": "translated value 2"}`;
}

export function parseResponse(response: string): TranslationMap {
  // Remove potential markdown code blocks
  let cleaned = response.trim();
  if (cleaned.startsWith("```json")) {
    cleaned = cleaned.slice(7);
  } else if (cleaned.startsWith("```")) {
    cleaned = cleaned.slice(3);
  }
  if (cleaned.endsWith("```")) {
    cleaned = cleaned.slice(0, -3);
  }
  cleaned = cleaned.trim();

  try {
    return JSON.parse(cleaned);
  } catch (error) {
    throw new Error(
      `Failed to parse Gemini response as JSON: ${error}\nResponse: ${response}`
    );
  }
}

export class GeminiTranslator {
  private model;

  constructor(apiKey: string) {
    const genAI = new GoogleGenerativeAI(apiKey);
    this.model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
  }

  async translate(
    entries: MergedEntry[],
    targetLanguage: string
  ): Promise<TranslationMap> {
    const prompt = buildPrompt(entries, targetLanguage);

    const result = await this.model.generateContent(prompt);
    const response = result.response.text();

    return parseResponse(response);
  }
}

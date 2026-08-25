import type { MergedEntry, TranslationMap } from "./types.js";

export interface RejectedTranslation {
  key: string;
  reason: string;
}

/**
 * Placeholder names in a string: `{name}`, `{{name}}`, and the argument name
 * of ICU messages (`{count, plural, ...}` — the identifier before the comma).
 * ICU branch bodies like `one {# item}` contribute nothing: `#` is not an
 * identifier.
 */
export function extractPlaceholders(text: string): Set<string> {
  const names = new Set<string>();
  for (const match of text.matchAll(/\{\{?\s*([A-Za-z0-9_]+)\s*[,}]/g)) {
    names.add(match[1]);
  }
  return names;
}

/**
 * The gate between the model's response and the merge. Model output is
 * untrusted input: keep only requested keys whose value is a non-empty string
 * and whose placeholder names match the source exactly. Rejected keys are
 * simply absent from `accepted`, so upstream they join droppedKeys — their
 * hash is not recorded and they are retried on the next run instead of being
 * written to disk and marked up to date.
 */
export function validateTranslations(
  requested: MergedEntry[],
  candidate: TranslationMap
): { accepted: TranslationMap; rejected: RejectedTranslation[] } {
  const accepted: TranslationMap = {};
  const rejected: RejectedTranslation[] = [];

  for (const entry of requested) {
    if (!(entry.key in candidate)) {
      continue; // not returned at all — already reported as dropped upstream
    }
    const value = candidate[entry.key];

    if (typeof value !== "string" || value.trim() === "") {
      rejected.push({
        key: entry.key,
        reason: `expected a non-empty string, got ${JSON.stringify(value)}`,
      });
      continue;
    }

    const wanted = extractPlaceholders(entry.value);
    const got = extractPlaceholders(value);
    const missing = [...wanted].filter((name) => !got.has(name));
    const invented = [...got].filter((name) => !wanted.has(name));
    if (missing.length > 0 || invented.length > 0) {
      const parts = [];
      if (missing.length > 0) parts.push(`missing {${missing.join("}, {")}}`);
      if (invented.length > 0) parts.push(`invented {${invented.join("}, {")}}`);
      rejected.push({
        key: entry.key,
        reason: `placeholder mismatch: ${parts.join("; ")}`,
      });
      continue;
    }

    accepted[entry.key] = value;
  }

  // Keys the model returned but nobody asked for are dropped without ceremony:
  // they cannot overwrite anything (the merge only adds accepted keys), and
  // most are artifacts like a stray "note" field.
  return { accepted, rejected };
}

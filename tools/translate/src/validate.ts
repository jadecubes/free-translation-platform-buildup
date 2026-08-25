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
 * written to disk and marked up to date. Keys the model returned but was
 * never asked for are ignored: the merge only adds accepted keys, so they
 * cannot overwrite anything.
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
      // Truncated: a wrong-shaped value can be arbitrarily large
      const shown = JSON.stringify(value)?.slice(0, 80) ?? String(value);
      rejected.push({
        key: entry.key,
        reason: `expected a non-empty string, got ${shown}`,
      });
      continue;
    }

    const wanted = extractPlaceholders(entry.value);
    const got = extractPlaceholders(value);
    const sameNames =
      wanted.size === got.size && [...wanted].every((name) => got.has(name));
    if (!sameNames) {
      rejected.push({
        key: entry.key,
        reason: `placeholder mismatch: source has [${[...wanted].join(", ")}], translation has [${[...got].join(", ")}]`,
      });
      continue;
    }

    accepted[entry.key] = value;
  }

  return { accepted, rejected };
}

import { describe, it, expect } from "vitest";
import { buildPrompt, parseResponse } from "./gemini.js";
import type { MergedEntry } from "./types.js";

describe("parseResponse", () => {
  it("parses clean JSON", () => {
    const input = '{"submit": "Soumettre", "cancel": "Annuler"}';
    expect(parseResponse(input)).toEqual({
      submit: "Soumettre",
      cancel: "Annuler",
    });
  });

  it("strips ```json fences", () => {
    const input = '```json\n{"submit": "Soumettre"}\n```';
    expect(parseResponse(input)).toEqual({ submit: "Soumettre" });
  });

  it("strips bare ``` fences", () => {
    const input = '```\n{"submit": "Soumettre"}\n```';
    expect(parseResponse(input)).toEqual({ submit: "Soumettre" });
  });

  it("throws on invalid JSON", () => {
    expect(() => parseResponse("not json")).toThrow(
      "Failed to parse Gemini response as JSON"
    );
  });

  it("handles whitespace around JSON", () => {
    const input = '  \n {"submit": "Soumettre"} \n ';
    expect(parseResponse(input)).toEqual({ submit: "Soumettre" });
  });
});

describe("buildPrompt", () => {
  it("includes key, value, and context", () => {
    const entries: MergedEntry[] = [
      { key: "submit", value: "Submit", context: "Button on forms" },
    ];
    const prompt = buildPrompt(entries, "French");
    expect(prompt).toContain("English to French");
    expect(prompt).toContain('"submit"');
    expect(prompt).toContain('"Submit"');
    expect(prompt).toContain("Context: Button on forms");
  });

  it("omits context line when context is undefined", () => {
    const entries: MergedEntry[] = [
      { key: "ok", value: "OK" },
    ];
    const prompt = buildPrompt(entries, "Japanese");
    expect(prompt).toContain('"ok"');
    expect(prompt).not.toContain("Context:");
  });

  it("includes multiple entries", () => {
    const entries: MergedEntry[] = [
      { key: "a", value: "A" },
      { key: "b", value: "B" },
    ];
    const prompt = buildPrompt(entries, "French");
    expect(prompt).toContain('"a"');
    expect(prompt).toContain('"b"');
  });
});

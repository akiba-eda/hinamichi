import { describe, it, expect } from "vitest";
import { ruleBasedSelect } from "../lib/agent/fallback.js";
import { cand } from "./helpers.js";

describe("rule-based fallback", () => {
  it("picks nearest safe shelter for earthquake", () => {
    const r = ruleBasedSelect([cand("A", { walkMin: 12 }), cand("B", { walkMin: 5 }), cand("C", { walkMin: 6, crowdPct: 100, full: true })], "earthquake");
    expect(r.chosen?.letter).toBe("B");
    expect(r.reasons).toHaveLength(3);
  });
  it("prefers dry & high shelter for heavy rain even if farther", () => {
    const r = ruleBasedSelect([cand("A", { walkMin: 5, flood: 3, elevationM: 1 }), cand("B", { walkMin: 14, flood: 0, elevationM: 9 })], "heavy_rain");
    expect(r.chosen?.letter).toBe("B");
  });
  it("prefers elevation for tsunami", () => {
    const r = ruleBasedSelect([cand("A", { walkMin: 4, elevationM: 1, tsunami: 1 }), cand("B", { walkMin: 18, elevationM: 20 })], "tsunami");
    expect(r.chosen?.letter).toBe("B");
  });
  it("returns null when everything is full", () => {
    expect(ruleBasedSelect([cand("A", { crowdPct: 100, full: true })], "earthquake").chosen).toBeNull();
  });
  it("falls back to a non-full candidate when all violate soft rules", () => {
    const r = ruleBasedSelect([cand("A", { flood: 2 }), cand("B", { flood: 3 })], "flood");
    expect(r.chosen?.letter).toBe("A");
  });
});

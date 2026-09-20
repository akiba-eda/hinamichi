import { describe, it, expect } from "vitest";
import { validateLetter } from "../lib/agent/validator.js";
import { cand } from "./helpers.js";

describe("SafetyValidator", () => {
  it("rejects flooded shelter during heavy rain", () => {
    const all = [cand("A", { flood: 3 }), cand("B", { flood: 0, walkMin: 15 })];
    expect(validateLetter("A", "heavy_rain", all)?.rule).toBe("flood_depth");
    expect(validateLetter("B", "heavy_rain", all)).toBeNull();
  });
  it("accepts flooded shelter during earthquake (rule is disaster-specific)", () => {
    const all = [cand("A", { flood: 3 })];
    expect(validateLetter("A", "earthquake", all)).toBeNull();
  });
  it("rejects full shelter", () => {
    expect(validateLetter("A", "earthquake", [cand("A", { crowdPct: 100, full: true })])?.rule).toBe("crowd_full");
  });
  it("rejects tsunami zone and low elevation when higher exists", () => {
    const all = [cand("A", { tsunami: 2 }), cand("B", { elevationM: 2 }), cand("C", { elevationM: 12, walkMin: 14 })];
    expect(validateLetter("A", "tsunami", all)?.rule).toBe("tsunami_zone");
    expect(validateLetter("B", "tsunami", all)?.rule).toBe("tsunami_low_elevation");
    expect(validateLetter("C", "tsunami", all)).toBeNull();
  });
  it("rejects too far only when a nearer option exists", () => {
    expect(validateLetter("A", "earthquake", [cand("A", { walkMin: 45 })])).toBeNull();
    expect(validateLetter("A", "earthquake", [cand("A", { walkMin: 45 }), cand("B", { walkMin: 10 })])?.rule).toBe("too_far");
  });
  it("rejects unknown letters", () => {
    expect(validateLetter("Z", "earthquake", [cand("A")])?.rule).toBe("unknown_candidate");
    expect(validateLetter(undefined, "earthquake", [cand("A")])?.rule).toBe("unknown_candidate");
  });
});

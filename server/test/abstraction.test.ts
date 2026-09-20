import { describe, it, expect } from "vitest";
import { abstractCandidates, assertNoCoordinates, sanitiseNote } from "../lib/agent/abstraction.js";
import { cand } from "./helpers.js";

describe("data minimisation", () => {
  it("abstract candidates carry no coordinates or names", () => {
    const abs = abstractCandidates([cand("A", { name: "南行徳小学校" }), cand("B")]);
    const s = JSON.stringify(abs);
    expect(s).not.toContain("南行徳");
    expect(s).not.toMatch(/lat|lng/);
    expect(abs[0]).toMatchObject({ id: "A", walkMin: 8, crowdPct: 20 });
    expect(() => assertNoCoordinates(abs)).not.toThrow();
  });
  it("assertNoCoordinates catches leaks", () => {
    expect(() => assertNoCoordinates({ lat: 35.68, lng: 139.76 })).toThrow();
    expect(() => assertNoCoordinates({ p: "35.68123,139.76123" })).toThrow();
    expect(() => assertNoCoordinates({ walkMin: 8, elevationM: 12.5 })).not.toThrow();
  });
  it("sanitises remarks", () => {
    expect(sanitiseNote("収容300人(体育館)")).toBe("収容人");
    expect(sanitiseNote("")).toBeUndefined();
  });
});

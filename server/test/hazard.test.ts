import { describe, it, expect } from "vitest";
import { classifyFlood } from "../lib/tools/hazard.js";
import { tileXY, haversineM, walkMinutes, offsetM } from "../lib/geo.js";

describe("hazard colour classification", () => {
  it("maps legend colours", () => {
    expect(classifyFlood(null)).toBe(0);
    expect(classifyFlood({ r: 0, g: 0, b: 0, a: 0 })).toBe(0);
    expect(classifyFlood({ r: 0xf7, g: 0xf5, b: 0xa9, a: 255 })).toBe(1);
    expect(classifyFlood({ r: 0xff, g: 0xb7, b: 0xb7, a: 255 })).toBe(3);
    expect(classifyFlood({ r: 0xdc, g: 0x7a, b: 0xdc, a: 255 })).toBe(6);
  });
  it("tolerates slight colour drift", () => {
    expect(classifyFlood({ r: 0xff, g: 0xd5, b: 0xbd, a: 200 })).toBe(2);
  });
});

describe("geo", () => {
  it("tile xy for Tokyo at z10 matches GSI example", () => {
    const t = tileXY({ lat: 35.68, lng: 139.76 }, 10);
    expect(t.x).toBe(909);
    expect(t.y).toBe(403);
  });
  it("distance & walking time", () => {
    const d = haversineM({ lat: 35.6588, lng: 139.9013 }, { lat: 35.6620, lng: 139.9060 });
    expect(d).toBeGreaterThan(500);
    expect(d).toBeLessThan(700);
    expect(walkMinutes(640)).toBe(8);
  });
  it("offset moves roughly the requested metres", () => {
    const p = { lat: 35.6588, lng: 139.9013 };
    const q = offsetM(p, 1000, 0);
    expect(Math.round(haversineM(p, q))).toBeGreaterThan(990);
    expect(Math.round(haversineM(p, q))).toBeLessThan(1010);
  });
});

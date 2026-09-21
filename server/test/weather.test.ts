import { describe, it, expect } from "vitest";
import { classifyRain } from "../lib/tools/weather.js";

const px = (r: number, g: number, b: number, a = 255) => ({ r, g, b, a });

describe("降水強度の凡例", () => {
  it("塗られていなければ 0", () => {
    expect(classifyRain(null)).toBe(0);
    expect(classifyRain(px(0, 0, 0, 0))).toBe(0);
  });

  it("凡例の色をそのまま当てる", () => {
    expect(classifyRain(px(0xf2, 0xf2, 0xff))).toBe(0.5);
    expect(classifyRain(px(0xa0, 0xd2, 0xff))).toBe(3);
    expect(classifyRain(px(0x00, 0x41, 0xff))).toBe(15);
    expect(classifyRain(px(0xb4, 0x00, 0x68))).toBe(100);
  });

  it("継ぎ目のわずかな滲みは吸収する", () => {
    expect(classifyRain(px(0xfa, 0xf0, 0x10))).toBe(25); // 20〜30mm/h の黄
  });

  it("凡例から遠い色は雨雲ではない(境界線や注記)", () => {
    expect(classifyRain(px(0x30, 0x30, 0x30))).toBe(0);
  });
});

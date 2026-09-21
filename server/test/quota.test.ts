import { describe, it, expect } from "vitest";
import { windowKey, dayKey, QUOTA } from "../lib/quota.js";

describe("回数制限の窓", () => {
  it("同じ10分の中なら同じ鍵になる", () => {
    const a = new Date("2026-09-22T05:03:00Z"), b = new Date("2026-09-22T05:09:59Z");
    expect(windowKey(a, 10)).toBe(windowKey(b, 10));
  });
  it("窓をまたぐと鍵が変わる(連打が次の窓に持ち越されない)", () => {
    const a = new Date("2026-09-22T05:09:59Z"), b = new Date("2026-09-22T05:10:00Z");
    expect(windowKey(a, 10)).not.toBe(windowKey(b, 10));
  });
  it("日の鍵は UTC の日付", () => {
    expect(dayKey(new Date("2026-09-22T23:59:59Z"))).toBe("2026-09-22");
    expect(dayKey(new Date("2026-09-23T00:00:00Z"))).toBe("2026-09-23");
  });
  it("発火の全体上限は1日のクレジットを数ドルに収める", () => {
    // 1回 $0.011。上限 × 単価が $5 を超えたら設定を見直す。
    expect(QUOTA.demoFire.globalPerDay! * 0.011).toBeLessThan(5);
  });
});

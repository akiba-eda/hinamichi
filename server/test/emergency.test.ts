import { describe, it, expect } from "vitest";
import { assertNoEmergencyPii, assertNoCoordinates } from "../lib/agent/abstraction.js";

/**
 * 「AI に個人情報を渡さない」を、約束ではなく仕組みにする。
 * ここが通らなくなったら、LLM へ送る前に例外で止まる。
 */
describe("緊急時情報が LLM への送信物に混ざっていないか", () => {
  const ok = {
    disaster: { type: "earthquake", title: "地震(最大震度6弱)", intensity: "6弱" },
    user: { areaName: "千葉県浦安市", nickname: "たろう" },
    candidatesPreview: [{ id: "A", walkMin: 6, elevationM: 1.2, crowdPct: 0 }],
  };

  it("ニックネームと市区町村だけなら通る", () => {
    expect(() => assertNoEmergencyPii(ok)).not.toThrow();
    expect(() => assertNoCoordinates(ok)).not.toThrow();
  });

  it("本名の項目が混ざったら止まる", () => {
    expect(() => assertNoEmergencyPii({ ...ok, user: { legalName: "山田太郎" } })).toThrow(/emergency PII/);
  });

  it("住所・年齢・電話の項目でも止まる", () => {
    for (const k of ["address", "age", "phone"]) {
      expect(() => assertNoEmergencyPii({ ...ok, extra: { [k]: "x" } }), k).toThrow(/emergency PII/);
    }
  });

  it("項目名を変えても、電話番号の形が入っていれば止まる", () => {
    expect(() => assertNoEmergencyPii({ ...ok, note: "連絡は 090-1234-5678 へ" })).toThrow(/phone-like/);
  });

  it("混雑率や徒歩分の数字は電話番号と誤認しない", () => {
    expect(() => assertNoEmergencyPii({ walkMin: 12, crowdPct: 30, elevationM: 3.3 })).not.toThrow();
  });

  it("assertNoCoordinates からも呼ばれる(既存の経路が自動で守られる)", () => {
    expect(() => assertNoCoordinates({ user: { legalName: "山田太郎" } })).toThrow(/emergency PII/);
  });
});

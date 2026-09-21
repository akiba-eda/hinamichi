import { describe, it, expect } from "vitest";
import { fixCounting } from "../lib/routes/senavi/ask.js";

/**
 * 「3件」を「どちらも」と書くのは、軽いモデルが実際にやる(実測3/3)。
 * プロンプトで直らないものを出力側で直している箇所なので、固定しておく。
 */
describe("件数の言い回しを直す", () => {
  it("3件のときの「どちらも」を件数に直す", () => {
    expect(fixCounting("3つあります。どちらも浸水想定はありません。", 3)).toContain("3件とも");
    expect(fixCounting("3つあります。どちらも浸水想定はありません。", 3)).not.toContain("どちらも");
  });

  it("2件のときは触らない(「どちらも」で正しい)", () => {
    const t = "2つあります。どちらも浸水想定はありません。";
    expect(fixCounting(t, 2)).toBe(t);
  });

  it("件数が分からないときは触らない", () => {
    const t = "どちらも浸水想定はありません。";
    expect(fixCounting(t, undefined)).toBe(t);
  });

  it("「どちらの避難場所も」のような形も拾う", () => {
    expect(fixCounting("どちらの避難場所も浸水想定はありません。", 3)).not.toContain("どちらの");
  });
});

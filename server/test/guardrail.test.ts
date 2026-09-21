import { describe, it, expect } from "vitest";
import { maskedEntities } from "../lib/routes/friends/message.js";

describe("ガードレールが伏せた項目を読む", () => {
  it("伏せ字のタグから何が止められたか分かる", () => {
    expect(maskedEntities("連絡先は [PHONE] です")).toEqual(["電話番号"]);
    expect(maskedEntities("[EMAIL] か [PHONE] へ")).toEqual(["メールアドレス", "電話番号"]);
  });

  it("同じ種類が何度出ても1つに数える", () => {
    expect(maskedEntities("[PHONE] と [PHONE]")).toEqual(["電話番号"]);
  });

  it("伏せ字が無ければ空", () => {
    expect(maskedEntities("3階にいます。無事です")).toEqual([]);
  });

  it("角括弧でも知らないタグは拾わない(本文の[重要]などを誤検知しない)", () => {
    expect(maskedEntities("[URGENT] 助けて")).toEqual([]);
  });

  it("伏せ字が1つでも出たら、整形結果は採用しない判定になる", () => {
    // message.ts は masked.length で原文送信に切り替える。
    // ここがゼロ判定だと、家族に [PHONE] が届いてしまう。
    expect(maskedEntities("連絡先は [PHONE] です。3階にいます").length).toBeGreaterThan(0);
    expect(maskedEntities("3階にいます。無事です").length).toBe(0);
  });
});

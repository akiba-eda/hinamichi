import { describe, it, expect } from "vitest";
import { deanonymise } from "../lib/agent/abstraction.js";

describe("セナヴィの一言から仮名を消す", () => {
  it("実データで出た文をそのまま直せる", () => {
    expect(deanonymise("今のうちにDへ避難すると安心だよ。")).toBe("今のうちにここへ避難すると安心だよ。");
    expect(deanonymise("大雨警報が出ているので、浸水の心配がなく高台にあるCへ早めに避難しましょうね。"))
      .toBe("大雨警報が出ているので、浸水の心配がなく高台にあるここへ早めに避難しましょうね。");
  });

  it("全角の仮名も拾う", () => {
    expect(deanonymise("Ｂへ向かおう")).toBe("ここへ向かおう");
  });

  it("英単語の一部は巻き込まない", () => {
    // GPS の G、AED の A を「ここ」にしてしまうと文が壊れる。
    expect(deanonymise("GPSが使えなくても大丈夫")).toBe("GPSが使えなくても大丈夫");
    expect(deanonymise("AEDのある場所だよ")).toBe("AEDのある場所だよ");
  });

  it("仮名が無い文はそのまま", () => {
    expect(deanonymise("今のうちに、ここへ避難しておこう")).toBe("今のうちに、ここへ避難しておこう");
  });
});

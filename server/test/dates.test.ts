import { describe, it, expect } from "vitest";
import { fixDates } from "../lib/routes/senavi/ask.js";

/**
 * 相対表現は、あとから画面を見返したときにいつの話か分からなくなる。
 * プロンプトで禁じても軽いモデルは質問文をなぞって「今日」と書く(実測2/5)ので、
 * 出力側で直している。
 */
describe("相対的な日付を日付に直す", () => {
  const now = new Date(2026, 8, 22); // 2026-09-22

  it("今日・明日・明後日を日付にする", () => {
    expect(fixDates("今日の天気は雨です", now)).toBe("9/22の天気は雨です");
    expect(fixDates("明日はくもり", now)).toBe("9/23はくもり");
    expect(fixDates("明後日は晴れ", now)).toBe("9/24は晴れ");
  });

  it("かな表記も拾う", () => {
    expect(fixDates("きょうは雨、あしたは晴れ", now)).toBe("9/22は雨、9/23は晴れ");
  });

  it("月をまたぐ", () => {
    expect(fixDates("明日は雨", new Date(2026, 8, 30))).toBe("10/1は雨");
  });

  it("相対表現が無ければ触らない", () => {
    const t = "9/22 18時からは降水確率100%です";
    expect(fixDates(t, now)).toBe(t);
  });
});

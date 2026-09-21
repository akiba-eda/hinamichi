import { describe, it, expect } from "vitest";
import { threadId } from "../lib/social.js";

describe("やりとりの置き場", () => {
  it("どちらから送っても同じ名前になる", () => {
    expect(threadId("bbb", "aaa")).toBe(threadId("aaa", "bbb"));
  });

  it("名前を割れば当事者が分かる(ルール側で使う)", () => {
    // firestore.rules は threadId.split('_') で当事者を判定している。
    expect(threadId("aaa", "bbb").split("_")).toEqual(["aaa", "bbb"]);
  });

  it("別の相手なら別の置き場", () => {
    expect(threadId("aaa", "bbb")).not.toBe(threadId("aaa", "ccc"));
  });
});

import { describe, it, expect } from "vitest";
import { membersAfterLeave } from "../lib/social.js";

describe("合流から抜ける", () => {
  it("押した人だけが外れ、他のメンバーの合流は続く", () => {
    const r = membersAfterLeave(["me", "a", "b"], "me");
    expect(r.members).toEqual(["a", "b"]);
    expect(r.active).toBe(true);
  });

  it("残りが1人になったら閉じる", () => {
    // 1人だけの合流は、旗が出たまま誰とも落ち合えない。残す意味が無い。
    const r = membersAfterLeave(["me", "a"], "me");
    expect(r.members).toEqual(["a"]);
    expect(r.active).toBe(false);
  });

  it("最後の1人が抜けたら空になって閉じる", () => {
    const r = membersAfterLeave(["me"], "me");
    expect(r.members).toEqual([]);
    expect(r.active).toBe(false);
  });

  it("メンバーでない人が呼んでも、顔ぶれを変えない", () => {
    const r = membersAfterLeave(["a", "b"], "me");
    expect(r.members).toEqual(["a", "b"]);
    expect(r.active).toBe(true);
  });

  it("重複が入っていても1人として数える", () => {
    // start と leave が競合して同じ uid が二重に入ることがある。
    // 重複を残すと「2人いる」と誤判定して、空の合流が active のまま残る。
    const r = membersAfterLeave(["me", "a", "a"], "me");
    expect(r.members).toEqual(["a"]);
    expect(r.active).toBe(false);
  });
});

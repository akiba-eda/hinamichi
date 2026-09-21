import { describe, it, expect } from "vitest";
import { placeCell } from "../lib/tools/areaCode.js";
import { offsetM } from "../lib/geo.js";

// 升目の真ん中。端に立つと 1m の移動でも隣の升目になるので、
// 「動いても変わらない」を確かめるならここから測る。
const center = { lat: 35.659, lng: 139.901 };

describe("placeCell", () => {
  it("升目の中で動く間は同じ鍵 = 逆ジオを引き直さない", () => {
    for (const [n, e] of [[30, 30], [-30, -30], [40, 0], [0, 40]]) {
      expect(placeCell(offsetM(center, n!, e!))).toBe(placeCell(center));
    }
  });

  it("1km 離れれば必ず別の鍵 = 区をまたぐ移動では引き直す", () => {
    expect(placeCell(offsetM(center, 1000, 0))).not.toBe(placeCell(center));
    expect(placeCell(offsetM(center, 0, 1000))).not.toBe(placeCell(center));
  });

  it("同じ地点は同じ鍵", () => {
    expect(placeCell(center)).toBe(placeCell({ ...center }));
  });
});

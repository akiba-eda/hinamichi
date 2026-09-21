import { describe, it, expect } from "vitest";
import { remainingAlongRoute } from "../lib/tools/route.js";
import { haversineM, offsetM } from "../lib/geo.js";

// 南行徳あたりで、東へ 400m 進んでから北へ 300m 曲がる L 字の経路。
const start = { lat: 35.6588, lng: 139.9013 };
const corner = offsetM(start, 400, 0);
const goal = offsetM(corner, 0, 300);
const leg = [start, corner, goal];

describe("remainingAlongRoute", () => {
  it("経路の全長を返す(出発地点にいるとき)", () => {
    const total = haversineM(start, corner) + haversineM(corner, goal);
    expect(remainingAlongRoute(leg, start)).toBeCloseTo(Math.round(total), -1);
  });

  it("曲がり角の手前では、直線距離ではなく曲がった分を含めて数える", () => {
    const here = offsetM(start, 300, 0); // 角まであと 100m
    const along = remainingAlongRoute(leg, here)!;
    // 直線なら斜めに約316mだが、実際は 100 + 300 = 400m 歩く
    expect(haversineM(here, goal)).toBeLessThan(330);
    expect(along).toBeGreaterThan(390);
    expect(along).toBeLessThan(410);
  });

  it("終点では 0 に近い", () => {
    expect(remainingAlongRoute(leg, goal)).toBeLessThan(2);
  });

  it("経路から大きく外れたら null(呼び出し側が直線距離に戻せるように)", () => {
    expect(remainingAlongRoute(leg, offsetM(start, 0, -500))).toBeNull();
  });

  it("頂点が足りない経路では測れない", () => {
    expect(remainingAlongRoute([start], start)).toBeNull();
  });
});

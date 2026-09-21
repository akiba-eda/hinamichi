import { describe, it, expect, vi, afterEach } from "vitest";
import { getAreaCode, UNKNOWN_AREA } from "../lib/tools/areaCode.js";
import { areaTopic } from "../lib/alerts.js";

const here = { lat: 35.6588, lng: 139.9013 };

afterEach(() => vi.unstubAllGlobals());

describe("逆ジオが落ちたとき", () => {
  it("getAreaCode 自体は失敗を隠さない", async () => {
    // /api/me/area はこの戻り値で FCM トピックを組む。黙って空を返すと
    // 端末が "area_" のような誤ったトピックを購読してしまうので、
    // 失敗は呼び出し側に見せる。
    vi.stubGlobal("fetch", async () => new Response("", { status: 503 }));
    await expect(getAreaCode(here)).rejects.toThrow();
  });

  it("市区町村が取れない点でも throw する", async () => {
    // 海上など、逆ジオが 200 を返しても市区町村が無い座標がある。
    vi.stubGlobal("fetch", async () => new Response(JSON.stringify({ results: null }), { status: 200 }));
    await expect(getAreaCode(here)).rejects.toThrow();
  });

  it("エージェントは UNKNOWN_AREA を受けて判断を続けられる", async () => {
    vi.stubGlobal("fetch", async () => new Response("", { status: 503 }));
    const area = await getAreaCode(here).catch(() => UNKNOWN_AREA);
    expect(area.name).toBe("現在地"); // 画面とプロンプトに出せる名前は残る
    expect(area.muniCd).toBe("");     // 判断以外には使わせない
  });

  it("UNKNOWN_AREA は警報の絞り込みに使えない形になっている", () => {
    // muniCd が空である限り loop.ts の areaKnown が false になり、
    // トピック配信や市区町村単位の絞り込みへは回らない。
    expect(UNKNOWN_AREA.jmaClass20).toBe("");
    expect(areaTopic(UNKNOWN_AREA.jmaClass20)).toBe("area_");
    expect(UNKNOWN_AREA.muniCd).toBe("");
  });
});

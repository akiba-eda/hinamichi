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

describe("LLM とフレンドに出す地名の粒度", () => {
  // 逆ジオ(lv01Nm は町丁目まで細かい)と、地理院の市区町村表の 2 本を返す fetch。
  const geocoder = JSON.stringify({ results: { muniCd: "12227", lv01Nm: "猫実二丁目" } });
  const muniJs = `GSI.MUNI_ARRAY["12227"] = '12,千葉県,12227,浦安市';`;

  it("市区町村で止める(町丁目は渡さない)", async () => {
    vi.resetModules(); // 市区町村表はモジュール内でキャッシュされるので毎回読み直す
    vi.stubGlobal("fetch", async (url: string) =>
      new Response(String(url).includes("muni.js") ? muniJs : geocoder, { status: 200 }));
    const { getAreaCode, getPlaceName } = await import("../lib/tools/areaCode.js");
    expect((await getAreaCode(here)).name).toBe("千葉県浦安市");
    expect(await getPlaceName(here)).toBe("千葉県浦安市");
  });

  it("市区町村表が引けなくても町丁目へは落とさない(都道府県だけ)", async () => {
    vi.resetModules();
    vi.stubGlobal("fetch", async (url: string) =>
      String(url).includes("muni.js") ? new Response("", { status: 503 }) : new Response(geocoder, { status: 200 }));
    const { getAreaCode } = await import("../lib/tools/areaCode.js");
    const area = await getAreaCode(here);
    expect(area.name).toBe("千葉県");
    expect(area.name).not.toContain("猫実");
    expect(area.muniCd).toBe("12227"); // 名前が粗くても警報の絞り込みは効く
  });
});

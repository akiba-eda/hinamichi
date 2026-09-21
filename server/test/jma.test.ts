import { describe, it, expect } from "vitest";
import { parseWarningDoc } from "../lib/sources/jma.js";

// 実物(VPWW53)の形を切り詰めたもの。市町村の塊と、同じ内容の粗いまとめが
// 両方入っている状態を再現している。
const DOC = `<Report>
<Warning type="気象警報・注意報（一次細分区域等）">
<Item>
<Kind><Name>大雨警報</Name><Code>03</Code><Condition>浸水害</Condition></Kind>
<Areas codeType="気象情報／府県予報区・細分区域等"><Area><Name>北西部</Name><Code>120010</Code></Area></Areas>
</Item>
</Warning>
<Warning type="気象警報・注意報（市町村等）">
<Item>
<Kind><Name>大雨警報</Name><Code>03</Code><Condition>土砂災害、浸水害</Condition></Kind>
<Kind><Name>洪水警報</Name><Code>04</Code></Kind>
<Kind><Name>雷注意報</Name><Code>14</Code></Kind>
<Areas codeType="気象・地震・火山情報／市町村等">
<Area><Name>市川市</Name><Code>1220300</Code></Area>
<Area><Name>船橋市</Name><Code>1220400</Code></Area>
</Areas>
</Item>
<Item>
<Kind><Name>大雨注意報</Name><Code>10</Code></Kind>
<Areas codeType="気象・地震・火山情報／市町村等"><Area><Name>浦安市</Name><Code>1222700</Code></Area></Areas>
</Item>
<Item>
<Kind><Name>大雨警報解除</Name><Code>03</Code></Kind>
<Areas codeType="気象・地震・火山情報／市町村等"><Area><Name>松戸市</Name><Code>1220700</Code></Area></Areas>
</Item>
</Warning>
</Report>`;

describe("気象警報 XML の読み取り", () => {
  const w = parseWarningDoc(DOC);

  it("市町村の塊だけを見る(粗いまとめを二重に数えない)", () => {
    expect(w.every((x) => x.areaCode.length === 7)).toBe(true);
    expect(w.some((x) => x.areaCode === "120010")).toBe(false);
  });

  it("1つの Item にぶら下がる市町村すべてに警報を配る", () => {
    const ichikawa = w.filter((x) => x.areaCode === "1220300").map((x) => x.name);
    expect(ichikawa).toEqual(["大雨警報", "洪水警報"]);
    expect(w.filter((x) => x.areaCode === "1220400").map((x) => x.name)).toEqual(["大雨警報", "洪水警報"]);
  });

  it("扱わないコード(雷注意報)は落とす", () => {
    expect(w.some((x) => x.code === "14")).toBe(false);
  });

  it("注意報は残すが level で見分けられる", () => {
    const urayasu = w.filter((x) => x.areaCode === "1222700");
    expect(urayasu.map((x) => x.level)).toEqual(["advisory"]);
  });

  it("解除は出ていないものとして扱う", () => {
    expect(w.some((x) => x.areaCode === "1220700")).toBe(false);
  });
});

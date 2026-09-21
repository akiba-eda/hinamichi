/**
 * 雨雲ナウキャスト — 気象庁 高解像度降水ナウキャスト(登録不要)。
 *
 * 数値予報モデル(Open-Meteo 等)ではなく**レーダー実観測**を使う。0〜60分・
 * 地点単位の「あと何分で降り出すか」は、いま見えているエコーの移動を外挿する
 * 方式でないと当たらない。モデルが有利になるのは数時間先から。
 *
 * 降水強度はタイル画像の色でしか配られていないので、ハザード判定と同じく
 * 現在地のピクセルを読んで凡例に当てる。
 */
import { PNG } from "pngjs";
import { tileXY, type LatLng } from "../geo.js";
import { getAreaCode, getPlaceName } from "./areaCode.js";

/** hrpns タイルはこれ以上拡大できない(z11 以上は空タイルが返る)。 */
const ZOOM = 10;
const NOWC = "https://www.jma.go.jp/bosai/jmatile/data/nowc";

export type RainNowcast = {
  nowMmh: number;
  maxMmh: number;
  /** 降り出すまでの分。いま降っている / 60分以内に降らないなら null。 */
  startsInMin: number | null;
  /** 止むまでの分。いま降っていない / 60分以内に止まないなら null。 */
  stopsInMin: number | null;
  /** 雲量の目安(%)。府県予報の天気コードから。取れなければ null。 */
  cloudPct: number | null;
  source: "jma_nowcast" | "unavailable";
};

/**
 * 降水強度の凡例(気象庁)。代表値は各階級の真ん中あたりを取る。
 * 色そのものが値なので、近い色に丸める(タイルの継ぎ目で滲むことがある)。
 */
const LEGEND: Array<{ mmh: number; rgb: [number, number, number] }> = [
  { mmh: 0.5, rgb: [0xf2, 0xf2, 0xff] },
  { mmh: 3, rgb: [0xa0, 0xd2, 0xff] },
  { mmh: 7, rgb: [0x21, 0x8c, 0xff] },
  { mmh: 15, rgb: [0x00, 0x41, 0xff] },
  { mmh: 25, rgb: [0xfa, 0xf5, 0x00] },
  { mmh: 40, rgb: [0xff, 0x99, 0x00] },
  { mmh: 65, rgb: [0xff, 0x28, 0x00] },
  { mmh: 100, rgb: [0xb4, 0x00, 0x68] },
];

export function classifyRain(px: { r: number; g: number; b: number; a: number } | null): number {
  if (!px || px.a < 40) return 0;
  let best = 0;
  let bestD = Infinity;
  for (const { mmh, rgb } of LEGEND) {
    const d = (px.r - rgb[0]) ** 2 + (px.g - rgb[1]) ** 2 + (px.b - rgb[2]) ** 2;
    if (d < bestD) {
      bestD = d;
      best = mmh;
    }
  }
  // どの凡例からも遠い色は雨雲ではない(境界線や注記の描き込み)。
  return bestD > 70 * 70 * 3 ? 0 : best;
}

type Frame = { basetime: string; validtime: string };

async function targetTimes(kind: "N1" | "N2"): Promise<Frame[]> {
  const r = await fetch(`${NOWC}/targetTimes_${kind}.json`, { headers: { "User-Agent": "hinamichi/0.1" }, signal: AbortSignal.timeout(6000) });
  if (!r.ok) return [];
  const j: any = await r.json();
  return Array.isArray(j) ? j.filter((x) => typeof x?.basetime === "string" && typeof x?.validtime === "string") : [];
}

/** "20260920172000" → epoch ms (UTC)。 */
function parseStamp(s: string): number {
  return Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8), +s.slice(8, 10), +s.slice(10, 12), 0);
}

async function rainAt(f: Frame, p: LatLng): Promise<number | null> {
  const t = tileXY(p, ZOOM);
  try {
    const r = await fetch(`${NOWC}/${f.basetime}/none/${f.validtime}/surf/hrpns/${ZOOM}/${t.x}/${t.y}.png`, {
      headers: { "User-Agent": "hinamichi/0.1" },
      signal: AbortSignal.timeout(6000),
    });
    if (!r.ok) return null;
    const png = PNG.sync.read(Buffer.from(await r.arrayBuffer()));
    // 雨が無い時間帯は 1x1 の空タイルが返るので、範囲外参照にならないよう丸める。
    if (t.px >= png.width || t.py >= png.height) return 0;
    const i = (t.py * png.width + t.px) * 4;
    return classifyRain({ r: png.data[i]!, g: png.data[i + 1]!, b: png.data[i + 2]!, a: png.data[i + 3]! });
  } catch {
    return null;
  }
}

/**
 * 市区町村コード → 気象庁の府県予報区(office)と一次細分区(class10)。
 *
 * 多くの県では office = 県コード+"0000" だが、北海道は 14、沖縄は 4 に
 * 分かれていて、鹿児島も奄美が別枠。決め打ちすると天気が引けない県が出るので、
 * 気象庁の区域表を引く。1 ファイル 260KB 程度なので、インスタンスごとに 1 回だけ。
 */
let areaTable: Promise<any> | null = null;
function areas(): Promise<any> {
  areaTable ??= fetch("https://www.jma.go.jp/bosai/common/const/area.json", {
    headers: { "User-Agent": "hinamichi/0.1" },
    signal: AbortSignal.timeout(8000),
  })
    .then((r) => (r.ok ? r.json() : null))
    .catch(() => null);
  return areaTable;
}

/**
 * 市区町村コード → 府県予報区(office)と一次細分区(class10)。
 *
 * 区域表のキーは市区町村コードと素直に一致しない。松本市は山間部が別枠で
 * 2020201/2020202 に割れているし、政令市の区は載らず市(0110000)で載っている。
 * 3 通り試して、当たったものを使う。
 */
async function forecastArea(muniCd: string): Promise<{ office: string; class10: string } | null> {
  const a = await areas();
  const table = a?.class20s;
  if (!table) return null;

  const exact = muniCd + "00";
  const split = Object.keys(table).find((k) => k.startsWith(muniCd)); // 市町村が細分されている場合
  const city = muniCd.slice(0, 3) + "0000"; // 政令市の区 → 市
  for (const k of [exact, split, city]) {
    if (!k) continue;
    const class15 = table[k]?.parent;
    const class10 = a?.class15s?.[class15]?.parent;
    const office = a?.class10s?.[class10]?.parent;
    if (typeof office === "string" && typeof class10 === "string") return { office, class10 };
  }
  return null;
}

/** 府県予報 JSON。予報を持たない office コードがあるので、県単位に落として一度だけ再試行する。 */
async function fetchForecast(codes: string[]): Promise<any | null> {
  for (const code of [...new Set(codes)]) {
    try {
      const r = await fetch(`https://www.jma.go.jp/bosai/forecast/data/forecast/${code}.json`, {
        headers: { "User-Agent": "hinamichi/0.1" },
        signal: AbortSignal.timeout(6000),
      });
      if (r.ok) return r.json();
    } catch {
      /* 次のコードを試す */
    }
  }
  return null;
}

/**
 * 府県予報の天気コードから雲量の目安を作る。
 *
 * レーダーは降水しか見ていないので、これが無いと「雨は降らなさそう」までしか
 * 言えず、「しばらく快晴みたい」が出せない。地域単位・更新も粗いが、
 * 空模様を一言添えるには足りる。
 */
async function cloudPct(p: LatLng): Promise<number | null> {
  try {
    const area = await getAreaCode(p);
    const fa = await forecastArea(area.muniCd);
    // 奄美(460040)のように予報 JSON を持たない office があり、その地域は県内の
    // 別の office(460100)の JSON に含まれる。県内の office を順に当たる。
    const inPref = Object.keys((await areas())?.offices ?? {}).filter((k) => k.startsWith(area.prefCd));
    const j = await fetchForecast([...(fa ? [fa.office] : []), area.prefCd + "0000", ...inPref]);
    const list: any[] = j?.[0]?.timeSeries?.[0]?.areas ?? [];
    if (!list.length) return null;
    // 細分区まで絞れなければ県の先頭。雲量は元々その程度の粒度。
    const mine = list.find((x) => x?.area?.code === fa?.class10) ?? list[0];
    const code = String(mine?.weatherCodes?.[0] ?? "");
    if (!code) return null;
    if (code === "100") return 10; // 晴
    if (code.startsWith("1")) return 40; // 晴ときどき曇 等
    if (code === "200") return 90; // くもり
    if (code.startsWith("2")) return 80;
    return 100; // 雨・雪
  } catch {
    return null;
  }
}

/** 今日・明日の見通し。レーダーの60分では答えられない問いのために引く。 */
export type Outlook = {
  areaName: string;
  /** 「今日」「明日」だけだと、いつの話か読み手に伝わらない。日付を持たせる。 */
  today?: { date: string; text: string; pops: Array<{ from: string; pct: number }> };
  tomorrow?: { date: string; text: string };
};

/**
 * 府県予報から、今日と明日の天気文と降水確率を取る。
 *
 * ナウキャストは 0〜60 分しか見ていないので、「今日は雨？」に答えられない。
 * 答えられない問いに答えさせないために、答えられる材料の方を足す。
 */
export async function getOutlook(p: LatLng): Promise<Outlook | null> {
  try {
    const area = await getAreaCode(p);
    const fa = await forecastArea(area.muniCd);
    const inPref = Object.keys((await areas())?.offices ?? {}).filter((k) => k.startsWith(area.prefCd));
    const j = await fetchForecast([...(fa ? [fa.office] : []), area.prefCd + "0000", ...inPref]);
    const series: any[] = j?.[0]?.timeSeries ?? [];
    const weather = series[0];
    const pop = series[1];
    const pick = (s: any) => (s?.areas ?? []).find((x: any) => x?.area?.code === fa?.class10) ?? s?.areas?.[0];
    const wa = pick(weather);
    const pa = pick(pop);
    if (!wa) return null;

    const times: string[] = weather?.timeDefines ?? [];
    const texts: string[] = wa?.weathers ?? [];
    // 降水確率は6時間ごと。今日ぶんだけ拾う。
    const popTimes: string[] = pop?.timeDefines ?? [];
    const pops: string[] = pa?.pops ?? [];
    const today = new Date().toISOString().slice(0, 10);
    const todayPops = popTimes
      .map((t, i) => ({ from: t, pct: Number(pops[i] ?? -1) }))
      .filter((x) => x.pct >= 0 && x.from.slice(0, 10) === today)
      // 「18:00から」ではなく「9/22 18:00から」と言えるように日付ごと渡す。
      .map((x) => ({ from: `${Number(x.from.slice(5, 7))}/${Number(x.from.slice(8, 10))} ${x.from.slice(11, 16)}`, pct: x.pct }));

    const md = (iso?: string) => (iso ? `${Number(iso.slice(5, 7))}/${Number(iso.slice(8, 10))}` : "");

    return {
      areaName: (await getPlaceName(p)) ?? area.name,
      ...(texts[0] ? { today: { date: md(times[0]), text: texts[0].replace(/[\s\u3000]+/g, ""), pops: todayPops } } : {}),
      ...(texts[1] ? { tomorrow: { date: md(times[1]), text: texts[1].replace(/[\s\u3000]+/g, "") } } : {}),
      ...(times.length ? {} : {}),
    };
  } catch {
    return null;
  }
}

export async function getRainNowcast(p: LatLng): Promise<RainNowcast> {
  const unavailable: RainNowcast = { nowMmh: 0, maxMmh: 0, startsInMin: null, stopsInMin: null, cloudPct: null, source: "unavailable" };
  const [obs, fc] = await Promise.all([targetTimes("N1"), targetTimes("N2")]);
  const now = obs[0]; // N1 は新しい順
  if (!now) return unavailable;

  const base = parseStamp(now.validtime);
  // 60分より先は「もう少しで」の話ではないので切る。
  const ahead = fc
    .filter((f) => parseStamp(f.validtime) > base && parseStamp(f.validtime) - base <= 60 * 60 * 1000)
    .sort((a, b) => parseStamp(a.validtime) - parseStamp(b.validtime));

  const [values, cloud] = await Promise.all([
    Promise.all([now, ...ahead].map((f) => rainAt(f, p))),
    cloudPct(p),
  ]);
  const nowMmh = values[0];
  if (nowMmh == null) return { ...unavailable, cloudPct: cloud };

  const future = ahead.map((f, i) => ({ min: Math.round((parseStamp(f.validtime) - base) / 60000), mmh: values[i + 1] ?? 0 }));
  const raining = (mmh: number) => mmh >= 0.5;

  return {
    nowMmh,
    maxMmh: Math.max(nowMmh, ...future.map((x) => x.mmh)),
    startsInMin: raining(nowMmh) ? null : (future.find((x) => raining(x.mmh))?.min ?? null),
    stopsInMin: raining(nowMmh) ? (future.find((x) => !raining(x.mmh))?.min ?? null) : null,
    cloudPct: cloud,
    source: "jma_nowcast",
  };
}

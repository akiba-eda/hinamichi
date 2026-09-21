import type { LatLng } from "../geo.js";

export type AreaInfo = {
  /** 5-digit 市区町村コード (JIS X 0402), e.g. "12203" = 市川市 */
  muniCd: string;
  /** JMA class20 code = muniCd + "00" */
  jmaClass20: string;
  /** 2-digit prefecture code */
  prefCd: string;
  /** JMA office code (prefecture level), e.g. "120000" */
  jmaOffice: string;
  name: string; // e.g. "千葉県市川市"
};

/**
 * 逆ジオが引けなかったときの入れ物。
 *
 * 市区町村コードを空にしてあるのは、**トピック名や警報の絞り込みに使わせない**ため。
 * 表示用の名前だけを持たせて、避難先の判断(座標とハザードで成立する)は続けさせる。
 */
export const UNKNOWN_AREA: AreaInfo = {
  muniCd: "",
  jmaClass20: "",
  prefCd: "",
  jmaOffice: "",
  name: "現在地",
};

/** GSI reverse geocoder → municipality code. No key. */
export async function getAreaCode(p: LatLng): Promise<AreaInfo> {
  const url = `https://mreversegeocoder.gsi.go.jp/reverse-geocoder/LonLatToAddress?lon=${p.lng}&lat=${p.lat}`;
  const r = await fetch(url, { headers: { "User-Agent": "hinamichi/0.1" } });
  if (!r.ok) throw new Error(`reverse geocoder ${r.status}`);
  const j: any = await r.json();
  const muniCd: string = String(j?.results?.muniCd ?? "");
  if (!/^\d{5}$/.test(muniCd)) throw new Error("no municipality for this point");
  const prefCd = muniCd.slice(0, 2);
  return {
    muniCd,
    jmaClass20: muniCd + "00",
    prefCd,
    jmaOffice: prefCd + "0000",
    name: `${PREF[prefCd] ?? ""}${j?.results?.lv01Nm ?? ""}`,
  };
}

/**
 * 市区町村コード → 「東京都足立区」。
 *
 * 逆ジオコーダが返す `lv01Nm` は町丁目(「猫実二丁目」)まで細かい。フレンドに
 * 見せる「最後にいた場所」はそこまで要らない ── というより、見せるべきでない。
 * 区市町村で止めるために、地理院の市区町村表を引く。100KB 程度なので
 * インスタンスごとに 1 回だけ読む。
 */
let muniTable: Promise<Record<string, string> | null> | null = null;
function muniNames(): Promise<Record<string, string> | null> {
  muniTable ??= fetch("https://maps.gsi.go.jp/js/muni.js", { headers: { "User-Agent": "hinamichi/0.1" }, signal: AbortSignal.timeout(8000) })
    .then(async (r) => {
      if (!r.ok) return null;
      const out: Record<string, string> = {};
      // 行の形: GSI.MUNI_ARRAY["13121"] = '13,東京都,13121,足立区';
      for (const m of (await r.text()).matchAll(/MUNI_ARRAY\["(\d+)"\]\s*=\s*'[^,]*,[^,]*,[^,]*,([^']*)'/g)) {
        // 地理院の表は「札幌市　中央区」のように全角空白が入ることがある。
        out[m[1]!.padStart(5, "0")] = m[2]!.replace(/[\s\u3000]+/g, "");
      }
      return Object.keys(out).length ? out : null;
    })
    .catch(() => null);
  return muniTable;
}

/**
 * 位置を丸めた升目。小数3桁 ≒ 110m 四方。
 *
 * 区市町村名はこの粒度では変わらないので、同じ升目なら逆ジオを引き直さない。
 * 境界をまたぐときだけ最大 110m ぶん古い区名が出うるが、「最後にいた場所」を
 * 区市町村で見せる用途では許容できる誤差。
 */
export function placeCell(p: LatLng): string {
  return `${p.lat.toFixed(3)},${p.lng.toFixed(3)}`;
}

const placeCache = new Map<string, string | null>();

/**
 * フレンドに見せる地名。「東京都足立区」まで。
 * 市区町村名が引けなければ都道府県だけ返す(空文字は返さない)。
 *
 * 位置は 50m 動くたびに届く。毎回逆ジオを引くと同じ答えを1日に何百回も
 * 取りに行くことになるので、升目単位で覚えておく。
 */
export async function getPlaceName(p: LatLng): Promise<string | null> {
  const cell = placeCell(p);
  if (placeCache.has(cell)) return placeCache.get(cell)!;
  let name: string | null = null;
  try {
    const area = await getAreaCode(p);
    const pref = PREF[area.prefCd] ?? "";
    const muni = (await muniNames())?.[area.muniCd] ?? "";
    name = `${pref}${muni}` || null;
  } catch {
    return null; // 一時的な失敗を覚え込まない
  }
  if (placeCache.size > 2000) placeCache.clear();
  placeCache.set(cell, name);
  return name;
}

export const PREF: Record<string, string> = {
  "01": "北海道", "02": "青森県", "03": "岩手県", "04": "宮城県", "05": "秋田県", "06": "山形県", "07": "福島県",
  "08": "茨城県", "09": "栃木県", "10": "群馬県", "11": "埼玉県", "12": "千葉県", "13": "東京都", "14": "神奈川県",
  "15": "新潟県", "16": "富山県", "17": "石川県", "18": "福井県", "19": "山梨県", "20": "長野県", "21": "岐阜県",
  "22": "静岡県", "23": "愛知県", "24": "三重県", "25": "滋賀県", "26": "京都府", "27": "大阪府", "28": "兵庫県",
  "29": "奈良県", "30": "和歌山県", "31": "鳥取県", "32": "島根県", "33": "岡山県", "34": "広島県", "35": "山口県",
  "36": "徳島県", "37": "香川県", "38": "愛媛県", "39": "高知県", "40": "福岡県", "41": "佐賀県", "42": "長崎県",
  "43": "熊本県", "44": "大分県", "45": "宮崎県", "46": "鹿児島県", "47": "沖縄県",
};

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

export const PREF: Record<string, string> = {
  "01": "北海道", "02": "青森県", "03": "岩手県", "04": "宮城県", "05": "秋田県", "06": "山形県", "07": "福島県",
  "08": "茨城県", "09": "栃木県", "10": "群馬県", "11": "埼玉県", "12": "千葉県", "13": "東京都", "14": "神奈川県",
  "15": "新潟県", "16": "富山県", "17": "石川県", "18": "福井県", "19": "山梨県", "20": "長野県", "21": "岐阜県",
  "22": "静岡県", "23": "愛知県", "24": "三重県", "25": "滋賀県", "26": "京都府", "27": "大阪府", "28": "兵庫県",
  "29": "奈良県", "30": "和歌山県", "31": "鳥取県", "32": "島根県", "33": "岡山県", "34": "広島県", "35": "山口県",
  "36": "徳島県", "37": "香川県", "38": "愛媛県", "39": "高知県", "40": "福岡県", "41": "佐賀県", "42": "長崎県",
  "43": "熊本県", "44": "大分県", "45": "宮崎県", "46": "鹿児島県", "47": "沖縄県",
};

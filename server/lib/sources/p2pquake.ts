/** P2P地震情報 API v2 — 551 (地震情報) / 556 (緊急地震速報). No key. Poll from server only. */
export type QuakeEvent = {
  id: string;
  time: string;
  hypocenterName: string;
  lat: number;
  lng: number;
  magnitude: number;
  depthKm: number;
  /** JMA seismic intensity as number: 4, 5 (5弱), 5.5 (5強), 6, 6.5, 7 */
  maxIntensity: number;
  maxIntensityLabel: string;
  /** prefectures where scale >= threshold */
  prefs: string[];
  tsunami: string;
};

const SCALE: Record<number, [number, string]> = {
  10: [1, "1"], 20: [2, "2"], 30: [3, "3"], 40: [4, "4"], 45: [5, "5弱"], 50: [5.5, "5強"], 55: [6, "6弱"], 60: [6.5, "6強"], 70: [7, "7"],
};

export async function fetchRecentQuakes(limit = 5): Promise<QuakeEvent[]> {
  const r = await fetch(`https://api.p2pquake.net/v2/history?codes=551&limit=${limit}`, { headers: { "User-Agent": "hinamichi/0.1" } });
  if (!r.ok) throw new Error(`p2pquake ${r.status}`);
  const arr: any[] = await r.json();
  return arr
    .filter((e) => e?.code === 551 && e?.earthquake?.hypocenter)
    .map((e) => {
      const sc = SCALE[e.earthquake.maxScale] ?? [0, "不明"];
      const th = 30;
      const prefs = Array.from(new Set((e.points ?? []).filter((p: any) => p.scale >= th).map((p: any) => p.pref))) as string[];
      return {
        id: String(e.id),
        time: e.earthquake.time,
        hypocenterName: e.earthquake.hypocenter.name,
        lat: e.earthquake.hypocenter.latitude,
        lng: e.earthquake.hypocenter.longitude,
        magnitude: e.earthquake.hypocenter.magnitude,
        depthKm: e.earthquake.hypocenter.depth,
        maxIntensity: sc[0],
        maxIntensityLabel: sc[1],
        prefs,
        tsunami: e.earthquake.domesticTsunami ?? "Unknown",
      };
    });
}

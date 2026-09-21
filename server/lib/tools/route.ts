import { haversineM, walkMinutes, type LatLng } from "../geo.js";

export type Route = {
  /**
   * 経路の頂点。
   *
   * `[lat, lng][]` にしたくなるが、**Firestore は配列の中に配列を置けない**
   * (INVALID_ARGUMENT: invalid nested entity)。incidents ドキュメントに
   * そのまま入るので、マップの配列にしてある。
   */
  points: { lat: number; lng: number }[];
  distanceM: number;
  durationS: number;
  provider: "ors" | "straight";
};

/** OpenRouteService foot-walking. Falls back to a straight line at 80 m/min. */
export async function getRoute(from: LatLng, to: LatLng): Promise<Route> {
  const key = process.env.ORS_API_KEY;
  if (key) {
    try {
      const r = await fetch("https://api.openrouteservice.org/v2/directions/foot-walking/geojson", {
        method: "POST",
        headers: { Authorization: key, "Content-Type": "application/json" },
        // 避難では距離が短い方が望ましい。既定の recommended は歩きやすさ優先。
        body: JSON.stringify({ coordinates: [[from.lng, from.lat], [to.lng, to.lat]], preference: "shortest" }),
        signal: AbortSignal.timeout(6000),
      });
      if (r.ok) {
        const j: any = await r.json();
        const f = j?.features?.[0];
        const coords: [number, number][] = f?.geometry?.coordinates ?? [];
        if (coords.length > 1) {
          return {
            points: coords.map(([lng, lat]) => ({ lat, lng })),
            distanceM: Math.round(f.properties?.summary?.distance ?? haversineM(from, to)),
            durationS: Math.round(f.properties?.summary?.duration ?? walkMinutes(haversineM(from, to)) * 60),
            provider: "ors",
          };
        }
      }
    } catch {
      /* fall through */
    }
  }
  const d = haversineM(from, to);
  return {
    points: [
      { lat: from.lat, lng: from.lng },
      { lat: to.lat, lng: to.lng },
    ],
    distanceM: Math.round(d),
    durationS: walkMinutes(d) * 60,
    provider: "straight",
  };
}


/**
 * 1 地点から複数地点への「道のり」をまとめて取る。
 *
 * 直線距離で候補を並べると順位が狂う。南行徳・浦安は川と運河で分断されていて、
 * 迂回率が候補ごとに 1.22〜1.66 倍とばらつくため(2026-09-21 実測)、一律の
 * 係数では吸収できない ── 直線では近いのに橋を回ると遠い候補を、AI が
 * 選んでしまう。
 *
 * directions を候補数だけ叩くと遅いので、matrix で 1 回にまとめる。
 * 失敗したら null を返し、呼び出し側は直線距離のまま進む(案内は止めない)。
 */
const matrixCache = new Map<string, { at: number; v: number[] }>();
const MATRIX_TTL_MS = 5 * 60 * 1000;

export async function getWalkDistances(from: LatLng, to: LatLng[]): Promise<number[] | null> {
  const key = process.env.ORS_API_KEY;
  if (!key || !to.length) return null;

  // 地図画面は現在地が動くたびに候補を引き直す。数十m動いただけで matrix を
  // 呼ぶと無料枠(1日500回)がデモの途中で尽きるので、約100mの升目に丸めて使い回す。
  const cacheKey = [from.lat.toFixed(3), from.lng.toFixed(3), ...to.map((p) => `${p.lat.toFixed(4)},${p.lng.toFixed(4)}`)].join("|");
  const hit = matrixCache.get(cacheKey);
  if (hit && Date.now() - hit.at < MATRIX_TTL_MS) return hit.v;

  try {
    const r = await fetch("https://api.openrouteservice.org/v2/matrix/foot-walking", {
      method: "POST",
      headers: { Authorization: key, "Content-Type": "application/json" },
      body: JSON.stringify({
        locations: [[from.lng, from.lat], ...to.map((p) => [p.lng, p.lat])],
        sources: [0],
        destinations: to.map((_, i) => i + 1),
        metrics: ["distance"],
      }),
      signal: AbortSignal.timeout(6000),
    });
    if (!r.ok) return null;
    const j: any = await r.json();
    const row: (number | null)[] | undefined = j?.distances?.[0];
    if (!Array.isArray(row) || row.length !== to.length) return null;
    // 到達できない候補は null で返るので、直線距離に委ねる。
    const v = row.map((m) => (typeof m === "number" ? Math.round(m) : -1));
    if (matrixCache.size > 200) matrixCache.clear();
    matrixCache.set(cacheKey, { at: Date.now(), v });
    return v;
  } catch {
    return null;
  }
}

/**
 * 案内中の「あと◯m」を、引いた経路に沿って測る。
 *
 * 直線距離だと、川や線路を回り込んでいる最中に「あと300m」と出てしまい、
 * 地図に描いてある線の長さと食い違う。位置更新のたびに経路APIを呼ぶわけには
 * いかない(無料枠・遅延)ので、保存済みの頂点列に現在地を落として残りを足す。
 *
 * 経路から大きく外れている場合は、その頂点列はもう本人の道筋ではないので
 * null を返す(呼び出し側が直線距離に戻す)。
 */
export function remainingAlongRoute(points: { lat: number; lng: number }[], p: LatLng, offRouteM = 200): number | null {
  if (points.length < 2) return null;

  // 末尾からの累積距離。suffix[i] = points[i] から終点までの長さ。
  const suffix = new Array<number>(points.length).fill(0);
  for (let i = points.length - 2; i >= 0; i--) suffix[i] = suffix[i + 1]! + haversineM(points[i]!, points[i + 1]!);

  let best: { off: number; remain: number } | null = null;
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i]!, b = points[i + 1]!;
    // 数百mの範囲なので、緯度補正した平面として扱えば十分。
    const kx = Math.cos((a.lat * Math.PI) / 180);
    const ax = a.lng * kx, ay = a.lat, bx = b.lng * kx, by = b.lat, px = p.lng * kx, py = p.lat;
    const dx = bx - ax, dy = by - ay;
    const len2 = dx * dx + dy * dy;
    const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
    const proj = { lat: ay + t * dy, lng: (ax + t * dx) / kx };
    const off = haversineM(p, proj);
    if (!best || off < best.off) best = { off, remain: haversineM(proj, b) + suffix[i + 1]! };
  }
  if (!best || best.off > offRouteM) return null;
  return Math.round(best.remain);
}

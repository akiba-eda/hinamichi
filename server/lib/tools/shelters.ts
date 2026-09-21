/**
 * 指定緊急避難場所 from 国土地理院 GeoJSON tiles (skhb01..08, z=10 only).
 * Layer per disaster type — so "type fit" is guaranteed by the data itself.
 */
import { createHash } from "node:crypto";
import { haversineM, tileXY, walkMinutes, bearingDeg, compass8, type LatLng } from "../geo.js";
import { getHazard, TileCache, type Hazard } from "./hazard.js";
import { getElevation } from "./elevation.js";
import { getWalkDistances } from "./route.js";

export type DisasterType = "earthquake" | "heavy_rain" | "flood" | "tsunami" | "landslide" | "storm_surge";

/** skhb layer numbers by disaster type. */
export const SKHB: Record<DisasterType, string> = {
  earthquake: "04",
  heavy_rain: "01", // 洪水 — heavy rain evacuations are flood-driven
  flood: "01",
  tsunami: "05",
  landslide: "02",
  storm_surge: "03",
};

export type Shelter = {
  id: string;
  name: string;
  address: string;
  remarks?: string;
  lat: number;
  lng: number;
  distanceM: number;
  walkMin: number;
  direction: string;
  elevationM?: number;
  hazard?: Hazard;
  layer: string; // skhb layer that returned it
  /** distanceM が実際の道のりか(false なら直線距離の目安)。 */
  routed?: boolean;
};

const GSI = "https://cyberjapandata.gsi.go.jp/xyz";

async function fetchTile(layer: string, x: number, y: number): Promise<any[]> {
  try {
    const r = await fetch(`${GSI}/skhb${layer}/10/${x}/${y}.geojson`, { headers: { "User-Agent": "hinamichi/0.1" } });
    if (!r.ok) return [];
    const j: any = await r.json();
    return Array.isArray(j?.features) ? j.features : [];
  } catch {
    return [];
  }
}

export function shelterId(name: string, lat: number, lng: number): string {
  return createHash("sha1").update(`${name}|${lat.toFixed(5)}|${lng.toFixed(5)}`).digest("hex").slice(0, 12);
}

/**
 * Candidates within radius, sorted by distance, enriched with elevation + hazard (for SafetyValidator).
 * Fetches the containing z10 tile plus neighbours when the point is near an edge.
 */
export async function listShelters(
  origin: LatLng,
  disasterType: DisasterType,
  opts: { radiusM?: number; limit?: number; enrich?: boolean; road?: boolean; cache?: TileCache } = {},
): Promise<Shelter[]> {
  const radiusM = opts.radiusM ?? 2500;
  const limit = opts.limit ?? 8;
  const layer = SKHB[disasterType];
  const t = tileXY(origin, 10);
  const xs = [t.x, ...(t.px < 48 ? [t.x - 1] : []), ...(t.px > 208 ? [t.x + 1] : [])];
  const ys = [t.y, ...(t.py < 48 ? [t.y - 1] : []), ...(t.py > 208 ? [t.y + 1] : [])];
  const tiles = await Promise.all(xs.flatMap((x) => ys.map((y) => fetchTile(layer, x, y))));
  const seen = new Set<string>();
  const out: Shelter[] = [];
  for (const f of tiles.flat()) {
    if (f?.geometry?.type !== "Point") continue;
    const [lng, lat] = f.geometry.coordinates as [number, number];
    const name: string = f.properties?.name ?? f.properties?.名称 ?? "避難場所";
    const id = shelterId(name, lat, lng);
    if (seen.has(id)) continue;
    seen.add(id);
    const d = haversineM(origin, { lat, lng });
    if (d > radiusM) continue;
    out.push({
      id,
      name,
      address: f.properties?.address ?? f.properties?.住所 ?? "",
      remarks: f.properties?.remarks ?? undefined,
      lat,
      lng,
      distanceM: Math.round(d),
      walkMin: walkMinutes(d),
      direction: compass8(bearingDeg(origin, { lat, lng })),
      layer,
    });
  }
  out.sort((a, b) => a.distanceM - b.distanceM);
  // 直線距離で絞ってから道のりを引く。迂回で順位が入れ替わりうるので、
  // limit より多めに残してから並べ直す。
  const top = out.slice(0, Math.min(out.length, limit * 2));

  // 候補ごとに迂回率が違う(南行徳では 1.22〜1.66 倍)ため、直線距離のままだと
  // 「直線では近いが橋を回ると遠い」候補が上に来てしまう。matrix で 1 回に
  // まとめて実距離へ差し替える。取れなければ直線のまま進む(案内は止めない)。
  if (opts.road !== false) {
    const roads = await getWalkDistances(origin, top.map((s) => ({ lat: s.lat, lng: s.lng })));
    if (roads) {
      top.forEach((s, i) => {
        const m = roads[i]!;
        if (m < 0) return;
        s.distanceM = m;
        s.walkMin = walkMinutes(m);
        s.routed = true;
      });
      top.sort((a, b) => a.distanceM - b.distanceM);
    }
  }
  top.splice(limit);

  if (opts.enrich !== false) {
    const cache = opts.cache ?? new TileCache();
    await Promise.all(
      top.map(async (s) => {
        const [elev, hz] = await Promise.all([getElevation(s), getHazard(s, cache)]);
        s.elevationM = elev;
        s.hazard = hz;
      }),
    );
  }
  return top;
}

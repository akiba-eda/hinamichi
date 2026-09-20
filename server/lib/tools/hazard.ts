/**
 * Hazard lookup from ハザードマップポータルサイト raster tiles (国土交通省).
 * We read the pixel under a point and map its colour to a class. Tiles are cached per request.
 */
import { PNG } from "pngjs";
import { tileXY, type LatLng } from "../geo.js";

export const HAZARD_BASE = "https://disaportaldata.gsi.go.jp/raster";
export const LAYERS = {
  flood: "01_flood_l2_shinsuishin_data", // 洪水浸水想定区域(想定最大規模)
  tsunami: "04_tsunami_newlegend_data", // 津波浸水想定
  debrisFlow: "05_dosekiryukeikaikuiki", // 土石流警戒区域
  steepSlope: "05_kyukeishakeikaikuiki", // 急傾斜地崩壊警戒区域
} as const;
export const HAZARD_ZOOM = 16;

/** Flood depth classes (想定最大規模 新凡例). 0 = none. */
export type FloodClass = 0 | 1 | 2 | 3 | 4 | 5 | 6;
export const FLOOD_LABEL: Record<FloodClass, string> = {
  0: "浸水想定なし",
  1: "0.5m未満",
  2: "0.5〜3m",
  3: "3〜5m",
  4: "5〜10m",
  5: "10〜20m",
  6: "20m以上",
};
// Legend colours (RGB). Matched by nearest colour so slight anti-aliasing is tolerated.
const FLOOD_LEGEND: Array<{ cls: FloodClass; rgb: [number, number, number] }> = [
  { cls: 1, rgb: [0xf7, 0xf5, 0xa9] },
  { cls: 2, rgb: [0xff, 0xd8, 0xc0] },
  { cls: 3, rgb: [0xff, 0xb7, 0xb7] },
  { cls: 4, rgb: [0xff, 0x91, 0x91] },
  { cls: 5, rgb: [0xf2, 0x85, 0xc9] },
  { cls: 6, rgb: [0xdc, 0x7a, 0xdc] },
];

export type Hazard = {
  flood: FloodClass;
  floodLabel: string;
  tsunami: FloodClass; // same legend family; 0 = none
  landslide: boolean;
  source: "tiles" | "unavailable";
};

export type Pixel = { r: number; g: number; b: number; a: number } | null;

export function classifyFlood(px: Pixel): FloodClass {
  if (!px || px.a < 40) return 0;
  let best: FloodClass = 0;
  let bestD = Infinity;
  for (const { cls, rgb } of FLOOD_LEGEND) {
    const d = (px.r - rgb[0]) ** 2 + (px.g - rgb[1]) ** 2 + (px.b - rgb[2]) ** 2;
    if (d < bestD) {
      bestD = d;
      best = cls;
    }
  }
  // If the colour is far from every legend entry, still treat "painted" as at least class 1.
  return bestD > 60 * 60 * 3 ? 1 : best;
}

export class TileCache {
  private cache = new Map<string, Promise<PNG | null>>();

  async tile(layer: string, z: number, x: number, y: number): Promise<PNG | null> {
    const key = `${layer}/${z}/${x}/${y}`;
    if (!this.cache.has(key)) this.cache.set(key, fetchTile(layer, z, x, y));
    return this.cache.get(key)!;
  }

  async pixel(layer: string, p: LatLng, z = HAZARD_ZOOM): Promise<Pixel> {
    const t = tileXY(p, z);
    const png = await this.tile(layer, z, t.x, t.y);
    if (!png) return null;
    const idx = (t.py * png.width + t.px) * 4;
    const d = png.data;
    return { r: d[idx]!, g: d[idx + 1]!, b: d[idx + 2]!, a: d[idx + 3]! };
  }
}

async function fetchTile(layer: string, z: number, x: number, y: number): Promise<PNG | null> {
  try {
    const r = await fetch(`${HAZARD_BASE}/${layer}/${z}/${x}/${y}.png`, {
      headers: { "User-Agent": "hinamichi/0.1" },
    });
    if (r.status === 404) return null; // no hazard data painted here
    if (!r.ok) return null;
    const buf = Buffer.from(await r.arrayBuffer());
    return PNG.sync.read(buf);
  } catch {
    return null;
  }
}

export async function getHazard(p: LatLng, cache = new TileCache()): Promise<Hazard> {
  try {
    const [f, t, d, s] = await Promise.all([
      cache.pixel(LAYERS.flood, p),
      cache.pixel(LAYERS.tsunami, p),
      cache.pixel(LAYERS.debrisFlow, p),
      cache.pixel(LAYERS.steepSlope, p),
    ]);
    const flood = classifyFlood(f);
    const tsunami = classifyFlood(t);
    const landslide = !!((d && d.a > 40) || (s && s.a > 40));
    return { flood, floodLabel: FLOOD_LABEL[flood], tsunami, landslide, source: "tiles" };
  } catch {
    return { flood: 0, floodLabel: FLOOD_LABEL[0], tsunami: 0, landslide: false, source: "unavailable" };
  }
}

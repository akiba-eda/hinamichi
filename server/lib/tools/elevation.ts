import type { LatLng } from "../geo.js";

const mem = new Map<string, Promise<number | undefined>>();

/** 国土地理院 標高API. Returns undefined when out of range ("-----"). Cached in-process. */
export async function getElevation(p: LatLng): Promise<number | undefined> {
  const key = `${p.lat.toFixed(4)},${p.lng.toFixed(4)}`;
  if (!mem.has(key)) {
    mem.set(
      key,
      (async () => {
        try {
          const url = `https://cyberjapandata2.gsi.go.jp/general/dem/scripts/getelevation.php?lon=${p.lng}&lat=${p.lat}&outtype=JSON`;
          const r = await fetch(url, { headers: { "User-Agent": "hinamichi/0.1" } });
          if (!r.ok) return undefined;
          const j: any = await r.json();
          const e = j?.elevation;
          return typeof e === "number" ? Math.round(e * 10) / 10 : undefined;
        } catch {
          return undefined;
        }
      })(),
    );
  }
  return mem.get(key)!;
}

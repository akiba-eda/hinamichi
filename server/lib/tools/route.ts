import { haversineM, walkMinutes, type LatLng } from "../geo.js";

export type Route = {
  /** [lat, lng][] */
  points: [number, number][];
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
        body: JSON.stringify({ coordinates: [[from.lng, from.lat], [to.lng, to.lat]] }),
        signal: AbortSignal.timeout(6000),
      });
      if (r.ok) {
        const j: any = await r.json();
        const f = j?.features?.[0];
        const coords: [number, number][] = f?.geometry?.coordinates ?? [];
        if (coords.length > 1) {
          return {
            points: coords.map(([lng, lat]) => [lat, lng] as [number, number]),
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
      [from.lat, from.lng],
      [to.lat, to.lng],
    ],
    distanceM: Math.round(d),
    durationS: walkMinutes(d) * 60,
    provider: "straight",
  };
}

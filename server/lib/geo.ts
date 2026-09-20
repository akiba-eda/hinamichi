/** Geo helpers: haversine, slippy-map tiles, bearing, walking time. */

export type LatLng = { lat: number; lng: number };

const R = 6371000;
const rad = (d: number) => (d * Math.PI) / 180;

export function haversineM(a: LatLng, b: LatLng): number {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** 80 m/min is the standard Japanese real-estate walking speed. */
export const WALK_M_PER_MIN = 80;
export const walkMinutes = (meters: number) => Math.max(1, Math.round(meters / WALK_M_PER_MIN));

export function bearingDeg(a: LatLng, b: LatLng): number {
  const y = Math.sin(rad(b.lng - a.lng)) * Math.cos(rad(b.lat));
  const x =
    Math.cos(rad(a.lat)) * Math.sin(rad(b.lat)) -
    Math.sin(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.cos(rad(b.lng - a.lng));
  return (((Math.atan2(y, x) * 180) / Math.PI) + 360) % 360;
}

export function compass8(deg: number): string {
  const names = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"];
  return names[Math.round(deg / 45) % 8]!;
}

/** Slippy map tile coordinates (Web Mercator). */
export function tileXY(p: LatLng, z: number): { x: number; y: number; px: number; py: number } {
  const n = 2 ** z;
  const xf = ((p.lng + 180) / 360) * n;
  const latR = rad(p.lat);
  const yf = ((1 - Math.log(Math.tan(latR) + 1 / Math.cos(latR)) / Math.PI) / 2) * n;
  const x = Math.floor(xf);
  const y = Math.floor(yf);
  return { x, y, px: Math.floor((xf - x) * 256), py: Math.floor((yf - y) * 256) };
}

/** Offset a point by meters (north/east) — used to fabricate a demo epicenter near the user. */
export function offsetM(p: LatLng, northM: number, eastM: number): LatLng {
  const dLat = northM / R;
  const dLng = eastM / (R * Math.cos(rad(p.lat)));
  return { lat: p.lat + (dLat * 180) / Math.PI, lng: p.lng + (dLng * 180) / Math.PI };
}

/** Coarse geohash-like cell key (~1.2 km) for caching hazard lookups without storing raw coords. */
export function cellKey(p: LatLng): string {
  return `${p.lat.toFixed(2)}_${p.lng.toFixed(2)}`;
}

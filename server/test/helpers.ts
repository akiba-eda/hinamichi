import type { CandidateCtx } from "../lib/agent/types.js";
import type { Shelter } from "../lib/tools/shelters.js";
import { FLOOD_LABEL, type FloodClass } from "../lib/tools/hazard.js";

export function cand(letter: string, o: Partial<Shelter> & { flood?: FloodClass; tsunami?: FloodClass; landslide?: boolean; crowdPct?: number; full?: boolean } = {}): CandidateCtx {
  const flood = o.flood ?? 0, tsunami = o.tsunami ?? 0;
  const shelter: Shelter = {
    id: o.id ?? `id_${letter}`, name: o.name ?? `避難所${letter}`, address: "", lat: 35.6, lng: 139.9,
    distanceM: o.distanceM ?? (o.walkMin ?? 8) * 80, walkMin: o.walkMin ?? 8, direction: "北", elevationM: o.elevationM ?? 10, layer: "04",
    hazard: { flood, floodLabel: FLOOD_LABEL[flood], tsunami, landslide: o.landslide ?? false, source: "tiles" },
  };
  const pct = o.crowdPct ?? 20;
  return { letter, shelter, crowd: { assigned: pct * 3, capacity: 300, pct, full: o.full ?? pct >= 100 } };
}

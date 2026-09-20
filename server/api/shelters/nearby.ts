import { z } from "zod";
import { route, body } from "../../lib/http.js";
import { listShelters } from "../../lib/tools/shelters.js";
import { getHazard, TileCache } from "../../lib/tools/hazard.js";
import { getCrowd } from "../../lib/tools/crowd.js";
import { normaliseDisaster } from "../../lib/agent/loop.js";

/** Peacetime map: nearby shelters for a disaster type + hazard at the user's point. Nothing is stored. */
export default route({ methods: ["POST"], auth: "user" }, async (req) => {
  const b = z.object({ lat: z.number(), lng: z.number(), type: z.string().default("earthquake"), radiusM: z.number().max(5000).default(2000) }).parse(body(req));
  const tiles = new TileCache();
  const type = normaliseDisaster(b.type);
  const [shelters, hazard] = await Promise.all([listShelters(b, type, { radiusM: b.radiusM, limit: 12, enrich: false }), getHazard(b, tiles)]);
  const crowd = await getCrowd(shelters.map((s) => s.id));
  return {
    type,
    hazardHere: hazard,
    shelters: shelters.map((s) => ({ id: s.id, name: s.name, address: s.address, lat: s.lat, lng: s.lng, distanceM: s.distanceM, walkMin: s.walkMin, crowdPct: crowd[s.id]?.pct ?? 0, full: crowd[s.id]?.full ?? false })),
  };
});

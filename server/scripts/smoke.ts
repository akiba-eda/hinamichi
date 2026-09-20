/**
 * Live smoke test of the real-data tools (no Firebase, no LLM). Run on your Mac:
 *   cd server && npx tsx scripts/smoke.ts 35.6588 139.9013      # 南行徳駅
 */
import { getAreaCode } from "../lib/tools/areaCode.js";
import { getHazard, TileCache } from "../lib/tools/hazard.js";
import { listShelters } from "../lib/tools/shelters.js";
import { getRoute } from "../lib/tools/route.js";

const lat = Number(process.argv[2] ?? 35.6588), lng = Number(process.argv[3] ?? 139.9013);
const here = { lat, lng };
const tiles = new TileCache();
console.log("area:", await getAreaCode(here));
console.log("hazard here:", await getHazard(here, tiles));
for (const t of ["earthquake", "heavy_rain", "tsunami"] as const) {
  const s = await listShelters(here, t, { cache: tiles, limit: 5 });
  console.log(`\n[${t}]`);
  for (const x of s) console.log(` ${x.walkMin}分 ${x.name} elev=${x.elevationM} flood=${x.hazard?.floodLabel} tsunami=${x.hazard?.tsunami} landslide=${x.hazard?.landslide}`);
  if (s[0]) console.log(" route:", (await getRoute(here, s[0])).provider);
}

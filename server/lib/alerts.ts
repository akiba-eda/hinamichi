/** Alert creation from real sources and from demo, plus broadcast. */
import { db, COL, FieldValue } from "./firebase.js";
import { fetchRecentQuakes } from "./sources/p2pquake.js";
import { fetchWarningsMap, type Warning } from "./sources/jma.js";
import { pushToTopic, pushToUsers } from "./agent/store.js";
import { offsetM } from "./geo.js";
import { getAreaCode } from "./tools/areaCode.js";
import type { AlertDoc, DisasterType } from "./agent/types.js";

export const TOPIC_ALL = "all";
export const MIN_QUAKE_INTENSITY = 4;

export async function createAlert(a: Omit<AlertDoc, "id"> & { id?: string }): Promise<AlertDoc> {
  const ref = a.id ? db().collection(COL.alerts).doc(a.id) : db().collection(COL.alerts).doc();
  const doc: AlertDoc = { ...a, id: ref.id };
  await ref.set({ ...JSON.parse(JSON.stringify(doc)), createdAt: FieldValue.serverTimestamp() });
  return doc;
}

const alertData = (a: AlertDoc) => ({ type: "alert", alertId: a.id, alertType: a.type, title: a.title, source: a.source });

/** Real alert → everyone (topic "all"). Users decide relevance via the agent. */
export async function broadcastAlert(a: AlertDoc) {
  await pushToTopic(TOPIC_ALL, `⚠️ ${a.title}`, "セナヴィがあなたへの影響を確認します。タップして開いてください", alertData(a));
}

/** Demo alert → only the requesting user's devices. */
export async function deliverDemoAlert(a: AlertDoc, uid: string) {
  await pushToUsers([uid], `⚠️ ${a.title}`, "セナヴィがあなたへの影響を確認します。タップして開いてください", { ...alertData(a), demo: "1" });
}

// ------------------------------------------------------------------ real sources

async function seen(key: string): Promise<boolean> {
  const ref = db().collection(COL.alertsSeen).doc(key);
  const s = await ref.get();
  if (s.exists) return true;
  await ref.set({ at: FieldValue.serverTimestamp() });
  return false;
}

export async function pollQuakes(): Promise<AlertDoc[]> {
  const out: AlertDoc[] = [];
  const quakes = await fetchRecentQuakes(5);
  for (const q of quakes) {
    if (q.maxIntensity < MIN_QUAKE_INTENSITY) continue;
    // Ignore events older than 30 minutes (cold start / backlog safety)
    if (Date.now() - new Date(q.time.replace(/\//g, "-")).getTime() > 30 * 60 * 1000) continue;
    if (await seen(`quake_${q.id}`)) continue;
    const a = await createAlert({
      type: "earthquake", source: "p2pquake", title: `地震(最大震度${q.maxIntensityLabel}・${q.hypocenterName})`,
      severity: Math.min(1, (q.maxIntensity - 3) / 4), intensity: q.maxIntensity, intensityLabel: q.maxIntensityLabel,
      areaCodes: [], // nationwide broadcast; the agent decides relevance by epicenter distance & pref
      epicenter: { lat: q.lat, lng: q.lng, name: q.hypocenterName }, issuedAt: new Date().toISOString(),
    });
    out.push(a);
  }
  return out;
}

export async function pollWarnings(): Promise<AlertDoc[]> {
  const out: AlertDoc[] = [];
  const warnings = await fetchWarningsMap();
  // Group new warning-level (or special) entries by (kind) across municipalities
  const relevant = warnings.filter((w) => w.level !== "advisory");
  const byKind = new Map<string, Warning[]>();
  for (const w of relevant) {
    const key = `${w.kind}`;
    byKind.set(key, [...(byKind.get(key) ?? []), w]);
  }
  for (const [kind, list] of byKind) {
    const codes = Array.from(new Set(list.map((w) => w.areaCode)));
    // A "new" alert = new set of municipalities for this kind within the last hour bucket
    const bucket = Math.floor(Date.now() / (60 * 60 * 1000));
    const key = `warn_${kind}_${bucket}_${hash(codes.join(","))}`;
    if (await seen(key)) continue;
    const names = Array.from(new Set(list.map((w) => w.name)));
    const special = list.some((w) => w.level === "special");
    const a = await createAlert({
      type: kindToDisaster(kind), source: "jma", title: names.join("・"), severity: special ? 1 : 0.6,
      warnings: names, areaCodes: codes, issuedAt: new Date().toISOString(),
    });
    out.push(a);
  }
  return out;
}

function kindToDisaster(kind: string): DisasterType {
  return ({ flood: "flood", heavy_rain: "heavy_rain", landslide: "landslide", tsunami: "tsunami", storm_surge: "storm_surge" } as Record<string, DisasterType>)[kind] ?? "heavy_rain";
}
function hash(s: string) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36);
}

// ------------------------------------------------------------------ demo

export type DemoScenario = "earthquake" | "heavy_rain" | "tsunami";

/** Build a demo alert anchored to the requesting device's current location (works at any venue). */
export async function createDemoAlert(uid: string, scenario: DemoScenario, here: { lat: number; lng: number }): Promise<AlertDoc> {
  const area = await getAreaCode(here);
  const epi = offsetM(here, 6000, 4000); // ~7 km NE of the user
  const base = { source: "demo" as const, areaCodes: [area.jmaClass20], issuedAt: new Date().toISOString(), demoTargetUid: uid };
  if (scenario === "earthquake") {
    return createAlert({ ...base, type: "earthquake", title: `地震(最大震度6弱・${area.name}付近)`, severity: 0.85, intensity: 6, intensityLabel: "6弱", epicenter: { lat: epi.lat, lng: epi.lng, name: `${area.name}付近` } });
  }
  if (scenario === "tsunami") {
    return createAlert({ ...base, type: "tsunami", title: "津波警報", severity: 0.95, warnings: ["津波警報"], epicenter: { lat: epi.lat, lng: epi.lng, name: "沖合" } });
  }
  return createAlert({ ...base, type: "heavy_rain", title: "大雨特別警報・洪水警報", severity: 0.9, warnings: ["大雨特別警報", "洪水警報"] });
}

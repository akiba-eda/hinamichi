/** Alert creation from real sources and from demo, plus broadcast. */
import { db, COL, FieldValue } from "./firebase.js";
import { fetchRecentQuakes } from "./sources/p2pquake.js";
import { fetchWarningDoc, fetchWarningFeed, type Warning } from "./sources/jma.js";
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

/** フィードに載ってから、これより古い文書は追わない(初回・復旧時の取りこぼし防止と暴発防止)。 */
const WARNING_MAX_AGE_MS = 30 * 60 * 1000;
/** 1 回のポーリングで引く文書の上限。全国一斉更新のときに時間を使い切らないため。 */
const WARNING_MAX_DOCS = 12;

export async function pollWarnings(): Promise<AlertDoc[]> {
  const feed = await fetchWarningFeed();

  // 前回見た文書は引き直さない。平常時にここを通るのは 0〜数件。
  const fresh: typeof feed = [];
  for (const e of feed) {
    if (Date.now() - new Date(e.updated).getTime() > WARNING_MAX_AGE_MS) continue;
    if (await seen(`warn_doc_${e.url.split("/").pop()}`)) continue;
    fresh.push(e);
    if (fresh.length >= WARNING_MAX_DOCS) break;
  }
  if (!fresh.length) return [];

  const out: AlertDoc[] = [];
  const docs = (await Promise.all(fresh.map(fetchWarningDoc))).filter((d): d is NonNullable<typeof d> => !!d);
  for (const doc of docs) {
    // 注意報は通知しない。鳴りすぎて警報が埋もれる。
    const relevant = doc.warnings.filter((w: Warning) => w.level !== "advisory");
    if (!relevant.length) continue;
    // 同じ文書の中でも種別ごとに分ける。大雨と高潮では避難先の選び方が変わる。
    const byKind = new Map<string, Warning[]>();
    for (const w of relevant) byKind.set(w.kind, [...(byKind.get(w.kind) ?? []), w]);
    for (const [kind, list] of byKind) {
      const names = Array.from(new Set(list.map((w) => w.name)));
      const a = await createAlert({
        type: kindToDisaster(kind),
        source: "jma",
        title: names.join("・"),
        severity: list.some((w) => w.level === "special") ? 1 : 0.6,
        warnings: names,
        areaCodes: Array.from(new Set(list.map((w) => w.areaCode))),
        issuedAt: doc.updated,
      });
      out.push(a);
    }
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

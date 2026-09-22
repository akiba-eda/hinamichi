/** Orchestration around runAgent: incident ids, idempotency, actions, reselection. */
import { z } from "zod";
import { db, COL, FieldValue } from "../firebase.js";
import { HttpError } from "../http.js";
import { runAgent, type RunOutput } from "./loop.js";
import { adjustCrowd } from "../tools/crowd.js";
import { haversineM, walkMinutes } from "../geo.js";
import { remainingAlongRoute } from "../tools/route.js";
import { incidentRef, notifyFriends, publishStatus, setIncident, IncidentLog } from "./store.js";
import { settledCost } from "../orca.js";
import type { AlertDoc, IncidentState, LocationSource } from "./types.js";

export const LocationBody = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  locationSource: z.enum(["gps", "cached", "manual"]).default("gps"),
});

export const incidentIdFor = (alertId: string, uid: string) => `${alertId}__${uid}`;

export async function loadAlert(alertId: string): Promise<AlertDoc> {
  const s = await db().collection(COL.alerts).doc(alertId).get();
  if (!s.exists) throw new HttpError(404, "この警報は見つかりませんでした", "not_found");
  return { id: s.id, ...(s.data() as any) } as AlertDoc;
}

export async function startIncident(opts: {
  uid: string; alertId: string; location: { lat: number; lng: number }; locationSource: LocationSource;
  demo?: { failLlm?: boolean }; force?: boolean;
}): Promise<{ incidentId: string; result: RunOutput; reused: boolean }> {
  const alert = await loadAlert(opts.alertId);
  if (alert.demoTargetUid && alert.demoTargetUid !== opts.uid) throw new HttpError(403, "この警報は別の端末向けです", "forbidden");
  const incidentId = incidentIdFor(alert.id, opts.uid);
  const existing = await incidentRef(incidentId).get();
  if (existing.exists && !opts.force) {
    const d = existing.data() as any;
    if (d.state && d.state !== "closed" && d.state !== "not_relevant") {
      return { incidentId, reused: true, result: { state: d.state, shelter: d.shelter, reasons: d.reasons ?? [], userMessage: d.userMessage ?? "", route: d.route, validatedBy: d.validatedBy ?? "none", costUsd: d.cost?.totalUsd ?? 0, llmCalls: d.cost?.llmCalls ?? 0 } };
    }
  }
  const result = await runAgent({ uid: opts.uid, incidentId, alert, location: opts.location, locationSource: opts.locationSource, demo: opts.demo });
  return { incidentId, result, reused: false };
}

export async function reselect(opts: { uid: string; incidentId: string; location: { lat: number; lng: number }; locationSource: LocationSource; reason: "crowd" | "user" | "alert" | "route"; demo?: { failLlm?: boolean } }) {
  const snap = await incidentRef(opts.incidentId).get();
  if (!snap.exists) throw new HttpError(404, "避難の記録が見つかりませんでした", "not_found");
  const d = snap.data() as any;
  if (d.uid !== opts.uid) throw new HttpError(403, "この避難はあなたのものではありません", "forbidden");
  const alert = await loadAlert(d.alertId);
  const prev = d.shelter?.id as string | undefined;
  await setIncident(opts.incidentId, { state: "reselecting", reselectReason: opts.reason });
  const log = new IncidentLog(opts.incidentId);
  log.add({ kind: "action", audience: "both", title: opts.reason === "crowd" ? "行き先が満員になったため再選定します" : opts.reason === "user" ? "「別の場所へ」が選ばれたため再選定します" : "状況が変わったため再選定します" });
  await log.flush();
  const result = await runAgent({ uid: opts.uid, incidentId: opts.incidentId, alert, location: opts.location, locationSource: opts.locationSource, demo: opts.demo, skipTriage: true, excludeShelterIds: prev ? [prev] : [], previousShelterId: prev });
  // Re-selection keeps the user in guiding (no new approval needed — same decision scope)
  if (result.state === "proposing") {
    await setIncident(opts.incidentId, { state: "guiding", startedAt: d.startedAt ?? new Date().toISOString() });
    await publishStatus(opts.uid, opts.incidentId, "guiding", result.shelter);
    await notifyFriends(opts.uid, "ヒナミチ", `行き先が変わりました: ${result.shelter?.name ?? ""}`, { type: "status", state: "evacuating", incidentId: opts.incidentId });
    result.state = "guiding";
  }
  return result;
}

export type Action = "start" | "later" | "arrived" | "safe_zone" | "close";

export async function applyAction(uid: string, incidentId: string, action: Action, via: "user" | "timeout" | "geofence") {
  const snap = await incidentRef(incidentId).get();
  if (!snap.exists) throw new HttpError(404, "避難の記録が見つかりませんでした", "not_found");
  const d = snap.data() as any;
  if (d.uid !== uid) throw new HttpError(403, "この避難はあなたのものではありません", "forbidden");
  const log = new IncidentLog(incidentId);
  let state: IncidentState = d.state;
  let friendMsg: string | undefined;

  switch (action) {
    case "start":
      state = "guiding";
      log.add({ kind: "approval", audience: "both", title: via === "timeout" ? "30秒応答がなかったため自動でナビを開始しました" : "「このルートで行く」が承認されました", detail: via === "timeout" ? "操作できない状況を想定し、AIが判断した経路で案内を続けます" : undefined });
      friendMsg = via === "timeout" ? `応答がありません。${d.shelter?.name ?? "避難場所"}へ誘導中です` : `${d.shelter?.name ?? "避難場所"}へ避難を開始しました`;
      await setIncident(incidentId, { state, startedAt: new Date().toISOString(), startedVia: via });
      break;
    case "later":
      state = "monitoring_stay";
      log.add({ kind: "approval", audience: "both", title: "「あとで確認する」が選ばれました", detail: "状況が悪化したらセナヴィが再度お知らせします" });
      await setIncident(incidentId, { state });
      break;
    case "arrived":
      state = "arrived";
      log.add({ kind: "action", audience: "both", title: via === "geofence" ? "避難場所に到着しました(位置情報で自動判定)" : "「到着した」が押されました" });
      friendMsg = `${d.shelter?.name ?? "避難場所"}に無事到着しました`;
      await setIncident(incidentId, { state, arrivedAt: new Date().toISOString(), closedAt: new Date().toISOString() });
      break;
    case "safe_zone":
      state = "safe_zone";
      log.add({ kind: "action", audience: "both", title: "安全な場所にいることを確認しました" });
      friendMsg = "安全な場所にいます";
      if (d.shelter?.id) await adjustCrowd(d.shelter.id, -1);
      await setIncident(incidentId, { state, closedAt: new Date().toISOString() });
      break;
    case "close":
      state = "closed";
      log.add({ kind: "action", audience: "both", title: "エージェントを終了しました" });
      if (d.shelter?.id && d.state !== "arrived") await adjustCrowd(d.shelter.id, -1);
      await setIncident(incidentId, { state, closedAt: new Date().toISOString() });
      break;
  }
  await log.flush();
  const pub = await publishStatus(uid, incidentId, state, d.shelter);
  if (friendMsg) await notifyFriends(uid, "ヒナミチ", friendMsg, { type: "status", state: pub, incidentId });
  if (state === "arrived" || state === "safe_zone" || state === "closed") void settleIncidentCost(incidentId).catch(() => {});
  return { state };
}

/** OrcaRouter: replace inline cost estimates with settled values from GET /v1/generation (設計書 §18 #11). */
export async function settleIncidentCost(incidentId: string) {
  const logs = await incidentRef(incidentId).collection("agentLog").get();
  const ids = logs.docs.map((d) => (d.data() as any).requestId).filter((x): x is string => typeof x === "string");
  if (!ids.length) return;
  const settled = await Promise.all(ids.map((id) => settledCost(id)));
  const total = settled.reduce<number>((a, b) => a + (b ?? 0), 0);
  const known = settled.filter((x) => x != null).length;
  const log = new IncidentLog(incidentId);
  log.add({ kind: "cost", audience: "judge", title: `確定コスト: $${total.toFixed(5)}(${known}/${ids.length} 件を /v1/generation で照合)`, detail: "OrcaRouter の確定値。インライン usage.cost_usd と食い違う場合はこちらが正" });
  await Promise.all([log.flush(), setIncident(incidentId, { cost: { settledUsd: total, settledCalls: known } })]);
}

/** Position update while guiding: arrival geofence (100 m). Nothing stored. */
export async function updatePosition(uid: string, incidentId: string, p: { lat: number; lng: number }) {
  const snap = await incidentRef(incidentId).get();
  if (!snap.exists) throw new HttpError(404, "避難の記録が見つかりませんでした", "not_found");
  const d = snap.data() as any;
  if (d.uid !== uid) throw new HttpError(403, "この避難はあなたのものではありません", "forbidden");
  if (!["guiding", "fallback_guiding", "reselecting"].includes(d.state) || !d.shelter) return { state: d.state as IncidentState, distanceM: null };
  // 到着判定は避難場所までの直線距離(ジオフェンス)、残り時間は経路に沿った長さ。
  // 役割が違うので分けている。
  const dist = haversineM(p, d.shelter);
  const along = Array.isArray(d.route?.points) ? remainingAlongRoute(d.route.points, p) : null;
  const remainingMin = Math.max(0, walkMinutes(along ?? dist));
  await incidentRef(incidentId).set({ remainingMin, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  if (dist <= 100) {
    const r = await applyAction(uid, incidentId, "arrived", "geofence");
    return { state: r.state, distanceM: Math.round(dist), remainingMin: 0 };
  }
  return { state: d.state as IncidentState, distanceM: Math.round(dist), remainingMin };
}

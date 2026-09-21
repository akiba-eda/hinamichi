/** Firestore persistence for incidents, agent log, public status and friend notifications. */
import { db, fcm, COL, FieldValue } from "../firebase.js";
import type { AgentLogEntry, AgentLogKind, IncidentState, PublicStatus } from "./types.js";

export class IncidentLog {
  private seq = 0;
  private buffer: AgentLogEntry[] = [];
  private costUsd = 0;
  constructor(public incidentId: string) {}

  add(e: Omit<AgentLogEntry, "seq" | "at">): AgentLogEntry {
    const entry: AgentLogEntry = { seq: ++this.seq, at: new Date().toISOString(), ...e };
    if (entry.costUsd) this.costUsd += entry.costUsd;
    this.buffer.push(entry);
    return entry;
  }
  info(title: string, detail?: string, audience: AgentLogEntry["audience"] = "both") {
    return this.add({ kind: "info", title, detail, audience });
  }
  get totalCostUsd() {
    return this.costUsd;
  }
  get entries() {
    return this.buffer;
  }

  /** Flush buffered entries in one batch (keeps Firestore writes low). */
  async flush() {
    if (!this.buffer.length) return;
    const batch = db().batch();
    const col = db().collection(COL.incidents).doc(this.incidentId).collection("agentLog");
    // doc id sorts chronologically across separate IncidentLog instances (run / reselect / actions)
    for (const e of this.buffer) batch.set(col.doc(`${e.at.replace(/[-:.TZ]/g, "")}_${String(e.seq).padStart(3, "0")}`), stripUndefined(e));
    this.buffer = [];
    await batch.commit();
  }
}

export function stripUndefined<T>(o: T): T {
  return JSON.parse(JSON.stringify(o));
}

export const incidentRef = (id: string) => db().collection(COL.incidents).doc(id);

export async function setIncident(id: string, data: Record<string, unknown>) {
  await incidentRef(id).set({ ...stripUndefined(data), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

export const stateToPublic = (s: IncidentState): PublicStatus =>
  s === "assessing" ? "assessing"
  : s === "guiding" || s === "reselecting" || s === "fallback_guiding" || s === "proposing" ? "evacuating"
  : s === "arrived" ? "arrived"
  : s === "safe_zone" ? "safe_zone"
  : "safe";

/**
 * Update the user's public status (what friends see) honouring consent.
 *
 * `note` には触らない ── あれは本人が書く一言(`/api/me/status`)で、
 * セナヴィの案内文で上書きすると「3階にいます」が消えてしまう。
 */
export async function publishStatus(uid: string, incidentId: string, state: IncidentState, shelter?: { name?: string; lat?: number; lng?: number }) {
  const user = (await db().collection(COL.users).doc(uid).get()).data() as any;
  const consent = user?.consent ?? {};
  const pub: PublicStatus = stateToPublic(state);
  const share = consent.shareShelterName !== false && shelter?.name;
  const doc: Record<string, unknown> = {
    state: pub,
    incidentId,
    shelterName: share ? shelter.name : null,
    // 行き先は名前だけだと地図に出せない。「地図で見る」で寄せるために座標も持たせる。
    // 本人の位置ではなく避難場所の位置なので、安否を共有する相手には見せてよい。
    shelterLat: share && shelter.lat != null ? shelter.lat : null,
    shelterLng: share && shelter.lng != null ? shelter.lng : null,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await db().collection(COL.statuses).doc(uid).set(doc, { merge: true });
  return pub;
}

/** Accepted friends who opted in to receive this user's status. */
export async function friendUids(uid: string): Promise<string[]> {
  const snap = await db().collection(COL.friends).doc(uid).collection("list").where("status", "==", "accepted").get();
  return snap.docs.filter((d) => (d.data() as any).autoShare !== false).map((d) => d.id);
}

export async function pushToUsers(uids: string[], title: string, body: string, data: Record<string, string> = {}) {
  if (!uids.length) return;
  const snaps = await db().getAll(...uids.map((u) => db().collection(COL.users).doc(u)));
  const tokens = snaps.map((s) => (s.data() as any)?.fcmToken).filter((t): t is string => typeof t === "string" && t.length > 0);
  if (!tokens.length) return;
  try {
    await fcm().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data,
      android: { priority: "high", notification: { channelId: "hinamichi_alerts", sound: "default" } },
      apns: { payload: { aps: { sound: "default" } } },
    });
  } catch (e) {
    console.warn("[fcm] multicast failed", e);
  }
}

export async function pushToTopic(topic: string, title: string, body: string, data: Record<string, string> = {}) {
  try {
    await fcm().send({
      topic,
      notification: { title, body },
      data,
      android: { priority: "high", notification: { channelId: "hinamichi_alerts", sound: "default" } },
      apns: { payload: { aps: { sound: "default", "content-available": 1 } } },
    });
  } catch (e) {
    console.warn("[fcm] topic send failed", e);
  }
}

export async function notifyFriends(uid: string, title: string, body: string, data: Record<string, string> = {}) {
  const user = (await db().collection(COL.users).doc(uid).get()).data() as any;
  if (user?.consent?.shareStatusWithFriends === false) return 0;
  const friends = await friendUids(uid);
  await pushToUsers(friends, title, body, { ...data, fromUid: uid });
  return friends.length;
}

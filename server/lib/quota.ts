import { db, COL, FieldValue } from "./firebase.js";
import { HttpError } from "./http.js";

/**
 * LLM のクレジットを消す経路の回数制限。
 *
 * デモ用の発火は誰でも叩ける(会場ビルドは毎回新しい匿名 uid なので、uid で
 * 絞ると成立しない)。その代わり、1人あたりの回数と全体の1日あたりの回数の
 * 二段で頭打ちにする。前者はうっかり連打、後者は uid を量産されたときの保険。
 *
 * 数えるのは Firestore の小さな doc 1〜2 個。窓の開始時刻を鍵にしているので、
 * 古い窓の doc は読まれなくなるだけで、消す仕組みは持たない。
 */
export type QuotaRule = { perUid: number; windowMin: number; globalPerDay?: number };

/** 窓の開始時刻(ms)を切り下げて鍵にする。同じ窓の呼び出しは同じ doc に集まる。 */
export function windowKey(now: Date, windowMin: number): string {
  const ms = windowMin * 60_000;
  return String(Math.floor(now.getTime() / ms) * ms);
}

export function dayKey(now: Date): string {
  return now.toISOString().slice(0, 10);
}

export async function assertQuota(uid: string, key: string, rule: QuotaRule, now = new Date()): Promise<void> {
  const col = db().collection(COL.quota);
  const uidRef = col.doc(`${key}_${uid}_${windowKey(now, rule.windowMin)}`);
  const globalRef = rule.globalPerDay ? col.doc(`${key}_global_${dayKey(now)}`) : null;

  await db().runTransaction(async (tx) => {
    const u = await tx.get(uidRef);
    const g = globalRef ? await tx.get(globalRef) : null;
    const uc = ((u.data() as any)?.count ?? 0) as number;
    const gc = ((g?.data() as any)?.count ?? 0) as number;
    if (uc >= rule.perUid) {
      throw new HttpError(429, `少し待ってからもう一度お試しください(${rule.windowMin}分に${rule.perUid}回まで)`, "rate_limited");
    }
    if (globalRef && rule.globalPerDay && gc >= rule.globalPerDay) {
      throw new HttpError(429, "今日の体験回数の上限に達しました。明日またお試しください", "rate_limited");
    }
    tx.set(uidRef, { count: uc + 1, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    if (globalRef) tx.set(globalRef, { count: gc + 1, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
}

/** 経路ごとの上限。数字はデモで困らない範囲で、連打と量産を止める値。 */
export const QUOTA = {
  /** 1回 $0.011。会場で1人が10分に10回も発火することはない。1日300回で約 $3。 */
  demoFire: { perUid: 10, windowMin: 10, globalPerDay: 300 } satisfies QuotaRule,
  agentRun: { perUid: 10, windowMin: 10 } satisfies QuotaRule,
  reselect: { perUid: 10, windowMin: 10 } satisfies QuotaRule,
  /** 1問 $0.00005 なので緩め。 */
  ask: { perUid: 30, windowMin: 10 } satisfies QuotaRule,
  message: { perUid: 30, windowMin: 10 } satisfies QuotaRule,
};

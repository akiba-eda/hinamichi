import { db, COL, FieldValue } from "../firebase.js";

/**
 * 収容人数の仮定値。
 *
 * **実データではない。** 国土地理院の指定緊急避難場所データが持っているのは
 * name / address / remarks / 災害種別フラグ だけで、収容人数は含まれない
 * (2026-09-21 に実タイルで確認)。自治体ごとのオープンデータを当たれば取れるが、
 * フォーマットがバラバラで、デモ地点以外をカバーできなくなる。
 *
 * したがって混雑率は「ヒナミチでそこへ向かっている人の割合」でしかない。
 * 実運用では自治体の避難所開設情報が正(設計書 Phase 2)。
 */
export const DEFAULT_CAPACITY = 300;

export type Crowd = { assigned: number; capacity: number; pct: number; full: boolean };

/**
 * デモで強制的に満員にしたかどうか。
 *
 * assigned を capacity ちょうどに積むだけだと、再選定時の adjustCrowd(-1) で
 * 1 人減って満員判定から外れ、2 回目のデモが効かなくなる。意図的な上書きは
 * 数の増減と別に持つ。
 */
type CrowdDoc = { assigned?: number; capacity?: number; forcedFull?: boolean; name?: string };

export async function getCrowd(ids: string[]): Promise<Record<string, Crowd>> {
  if (!ids.length) return {};
  const refs = ids.map((id) => db().collection(COL.shelterCrowd).doc(id));
  const snaps = await db().getAll(...refs);
  const out: Record<string, Crowd> = {};
  snaps.forEach((s, i) => {
    const d: CrowdDoc = s.exists ? (s.data() as CrowdDoc) : {};
    const assigned = Number(d.assigned ?? 0);
    const capacity = Number(d.capacity ?? DEFAULT_CAPACITY);
    const full = d.forcedFull === true || assigned >= capacity;
    out[ids[i]!] = { assigned, capacity, pct: full ? 100 : Math.min(100, Math.round((assigned / capacity) * 100)), full };
  });
  return out;
}

/** +1 when a user commits to a shelter, -1 when they leave/switch. Never below 0. */
export async function adjustCrowd(id: string, delta: number, name?: string) {
  const ref = db().collection(COL.shelterCrowd).doc(id);
  await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const cur = s.exists ? Number((s.data() as any).assigned ?? 0) : 0;
    tx.set(
      ref,
      { assigned: Math.max(0, cur + delta), capacity: s.exists ? (s.data() as any).capacity ?? DEFAULT_CAPACITY : DEFAULT_CAPACITY, name: name ?? (s.data() as any)?.name ?? null, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  });
}

/** デモ: 避難所を満員にする / 戻す。何度押しても同じ結果になるようにする。 */
export async function setCrowdFull(id: string, full: boolean, name?: string) {
  const ref = db().collection(COL.shelterCrowd).doc(id);
  const s = await ref.get();
  const capacity = s.exists ? Number((s.data() as CrowdDoc).capacity ?? DEFAULT_CAPACITY) : DEFAULT_CAPACITY;
  await ref.set(
    {
      assigned: full ? capacity : Math.round(capacity * 0.3),
      capacity,
      forcedFull: full,
      name: name ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

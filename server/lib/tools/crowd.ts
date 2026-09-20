import { db, COL, FieldValue } from "../firebase.js";

export const DEFAULT_CAPACITY = 300;

export type Crowd = { assigned: number; capacity: number; pct: number; full: boolean };

export async function getCrowd(ids: string[]): Promise<Record<string, Crowd>> {
  if (!ids.length) return {};
  const refs = ids.map((id) => db().collection(COL.shelterCrowd).doc(id));
  const snaps = await db().getAll(...refs);
  const out: Record<string, Crowd> = {};
  snaps.forEach((s, i) => {
    const d = s.exists ? (s.data() as any) : {};
    const assigned = Number(d.assigned ?? 0);
    const capacity = Number(d.capacity ?? DEFAULT_CAPACITY);
    out[ids[i]!] = { assigned, capacity, pct: Math.min(100, Math.round((assigned / capacity) * 100)), full: assigned >= capacity };
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

export async function setCrowdFull(id: string, full: boolean, name?: string) {
  const ref = db().collection(COL.shelterCrowd).doc(id);
  const s = await ref.get();
  const capacity = s.exists ? Number((s.data() as any).capacity ?? DEFAULT_CAPACITY) : DEFAULT_CAPACITY;
  await ref.set({ assigned: full ? capacity : Math.round(capacity * 0.3), capacity, name: name ?? null, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

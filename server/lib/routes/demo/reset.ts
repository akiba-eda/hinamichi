import { route, requireDemoAdmin } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";

/** Demo: close the caller's incidents, clear crowd counters they affected, reset own status. */
export default route({ methods: ["POST"], auth: "user" }, async (_req, _res, ctx) => {
  requireDemoAdmin(ctx.uid!);
  const uid = ctx.uid!;
  const inc = await db().collection(COL.incidents).where("uid", "==", uid).get();
  const batch = db().batch();
  const shelterIds = new Set<string>();
  for (const d of inc.docs) {
    const s = (d.data() as any).shelter?.id;
    if (s) shelterIds.add(s);
    batch.set(d.ref, { state: "closed", closedAt: new Date().toISOString() }, { merge: true });
  }
  for (const id of shelterIds) batch.set(db().collection(COL.shelterCrowd).doc(id), { assigned: 0, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  batch.set(db().collection(COL.statuses).doc(uid), { state: "safe", shelterName: null, note: null, incidentId: null, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await batch.commit();
  return { ok: true, closedIncidents: inc.size, clearedShelters: shelterIds.size };
});

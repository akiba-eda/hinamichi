import { z } from "zod";
import { route, body, requireDemoAdmin } from "../../lib/http.js";
import { db, COL, FieldValue } from "../../lib/firebase.js";

const MOCK = [
  { key: "mock_mother", displayName: "お母さん", relation: "家族" },
  { key: "mock_yuta", displayName: "ゆうた", relation: "友人" },
  { key: "mock_sakura", displayName: "さくら", relation: "同僚" },
];

/**
 * Demo friends (Firestore-only users). seed → three friends in "safe";
 * advance → they progress safe→assessing→evacuating→arrived; reset → back to safe.
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  requireDemoAdmin(ctx.uid!);
  const { action } = z.object({ action: z.enum(["seed", "advance", "reset"]) }).parse(body(req));
  const uid = ctx.uid!;
  const batch = db().batch();
  const order = ["safe", "assessing", "evacuating", "arrived"];
  for (const [i, m] of MOCK.entries()) {
    const fid = `${m.key}_${uid.slice(0, 6)}`;
    const statusRef = db().collection(COL.statuses).doc(fid);
    if (action === "seed") {
      batch.set(db().collection(COL.users).doc(fid), { displayName: m.displayName, isMock: true, createdAt: FieldValue.serverTimestamp() }, { merge: true });
      batch.set(db().collection(COL.friends).doc(uid).collection("list").doc(fid), { status: "accepted", autoShare: true, displayName: m.displayName, relation: m.relation, isMock: true }, { merge: true });
      batch.set(db().collection(COL.friends).doc(fid).collection("list").doc(uid), { status: "accepted", autoShare: true }, { merge: true });
      batch.set(statusRef, { state: "safe", shelterName: null, note: null, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    } else if (action === "reset") {
      batch.set(statusRef, { state: "safe", shelterName: null, note: null, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    } else {
      const cur = ((await statusRef.get()).data() as any)?.state ?? "safe";
      // stagger: friend i advances only if its index <= number of advances so far
      const next = order[Math.min(order.length - 1, order.indexOf(cur) + 1)]!;
      const shelterName = next === "evacuating" || next === "arrived" ? ["南行徳小学校", "行徳高校", "市川市立第七中学校"][i] : null;
      const note = next === "assessing" ? "確認中…" : next === "evacuating" ? "避難所へ向かっています" : next === "arrived" ? "到着しました" : null;
      // "mai" style unknown: leave last friend one step behind
      if (i === MOCK.length - 1 && next === "arrived") continue;
      batch.set(statusRef, { state: next, shelterName, note, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
  }
  await batch.commit();
  return { ok: true, action };
});

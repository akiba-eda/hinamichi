import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";
import { cardOf } from "../../profile.js";

/** Add a friend by invite code. Both sides become "accepted" immediately (hackathon simplification). */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const { code, relation } = z.object({ code: z.string().length(6), relation: z.string().max(10).optional() }).parse(body(req));
  const q = await db().collection(COL.users).where("inviteCode", "==", code.toUpperCase()).limit(1).get();
  if (q.empty) throw new HttpError(404, "招待コードが見つかりません", "not_found");
  const other = q.docs[0]!;
  if (other.id === ctx.uid) throw new HttpError(400, "自分のコードです", "bad_request");
  const me = (await db().collection(COL.users).doc(ctx.uid!).get()).data() as any;
  const batch = db().batch();
  // 位置共有は既定で false のまま。追加した時点では現在地を見せない(設計書 §5.1)。
  batch.set(db().collection(COL.friends).doc(ctx.uid!).collection("list").doc(other.id), { status: "accepted", autoShare: true, ...cardOf(other.data()), relation: relation ?? null, createdAt: FieldValue.serverTimestamp() }, { merge: true });
  batch.set(db().collection(COL.friends).doc(other.id).collection("list").doc(ctx.uid!), { status: "accepted", autoShare: true, ...cardOf(me), relation: null, createdAt: FieldValue.serverTimestamp() }, { merge: true });
  await batch.commit();
  return { friendUid: other.id, displayName: (other.data() as any).displayName };
});

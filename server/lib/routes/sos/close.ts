import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";

/** 依頼を取り下げる。本人か、受け取ったフレンドが閉じられる。 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const { sosId } = z.object({ sosId: z.string() }).parse(body(req));
  const ref = db().collection(COL.sos).doc(sosId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpError(404, "依頼が見つかりません", "not_found");
  const d = snap.data() as any;
  if (d.uid !== ctx.uid && !(d.recipients ?? []).includes(ctx.uid)) {
    throw new HttpError(403, "この依頼の当事者ではありません", "forbidden");
  }
  await ref.set({ active: false, closedAt: FieldValue.serverTimestamp(), closedBy: ctx.uid }, { merge: true });
  // 閉じたら個人情報も見えなくする。開きっぱなしにしない。
  await db().collection(COL.emergency).doc(d.uid).set({ revealedTo: [] }, { merge: true });
  return { ok: true };
});

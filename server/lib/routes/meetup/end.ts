import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";

/** 合流を終わる。メンバーなら誰でも終われる(待ち合わせは着いた人が閉じる)。 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const { meetupId } = z.object({ meetupId: z.string() }).parse(body(req));
  const ref = db().collection(COL.meetups).doc(meetupId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpError(404, "合流が見つかりません", "not_found");
  const members: string[] = (snap.data() as any)?.memberUids ?? [];
  if (!members.includes(ctx.uid!)) throw new HttpError(403, "この合流のメンバーではありません", "forbidden");
  await ref.set({ active: false, endedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { ok: true };
});

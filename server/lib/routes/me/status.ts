import { z } from "zod";
import { route, body } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";

/**
 * 本人が書く一言(メモ)。平時は「今日は在宅」、災害時は「3階にいます」など。
 * 状態の5段階では伝わらないことを本人の言葉で補う欄なので、
 * エージェントはここを書き換えない。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const { note } = z.object({ note: z.string().max(140) }).parse(body(req));
  await db()
    .collection(COL.statuses)
    .doc(ctx.uid!)
    .set({ note: note.trim() || null, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { ok: true };
});

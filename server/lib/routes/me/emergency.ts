import { z } from "zod";
import { route, body } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";

const Body = z.object({
  /** 本名。通報を代行してもらうために要る。ニックネーム(users.displayName)とは別。 */
  legalName: z.string().min(1).max(40),
  address: z.string().max(120).optional(),
  age: z.number().int().min(0).max(120).optional(),
  phone: z.string().max(20).optional(),
});

/**
 * 緊急時情報の保存。
 *
 * **ここに入るものは LLM に一切渡らない。** users/{uid} と分けてあるのは、
 * 同じドキュメントに置くと「プロフィールを読んでプロンプトに入れる」コードが
 * いつか生まれるから。物理的に別の場所に置いて、取りに行かないと触れない
 * ようにしてある。
 *
 * 読めるのは本人と、本人が出した SOS を受け取ったフレンドだけ(revealedTo)。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = Body.parse(body(req));
  await db()
    .collection(COL.emergency)
    .doc(ctx.uid!)
    .set(
      {
        legalName: b.legalName.trim(),
        address: b.address?.trim() || null,
        age: b.age ?? null,
        phone: b.phone?.trim() || null,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return { ok: true };
});

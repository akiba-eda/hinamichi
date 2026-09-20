import { z } from "zod";
import { route, body } from "../../http.js";
import { db, COL } from "../../firebase.js";

/** Toggle auto-share for one friend. */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const { friendUid, autoShare } = z.object({ friendUid: z.string(), autoShare: z.boolean() }).parse(body(req));
  await db().collection(COL.friends).doc(ctx.uid!).collection("list").doc(friendUid).set({ autoShare }, { merge: true });
  return { ok: true };
});

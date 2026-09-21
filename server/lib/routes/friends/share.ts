import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { db, COL } from "../../firebase.js";

const Body = z.object({
  friendUid: z.string(),
  /** 安否(5段階)を自動で届けるか。 */
  autoShare: z.boolean().optional(),
  /** この相手に現在地を見せるか。既定は false ── 相手ごとに明示的に許可する。 */
  shareLocation: z.boolean().optional(),
});

/** Toggle what one friend receives. Sends only the flags the caller passed. */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = Body.parse(body(req));
  if (b.autoShare === undefined && b.shareLocation === undefined) throw new HttpError(400, "何も指定されていません", "bad_request");
  await db()
    .collection(COL.friends)
    .doc(ctx.uid!)
    .collection("list")
    .doc(b.friendUid)
    .set(
      {
        ...(b.autoShare !== undefined ? { autoShare: b.autoShare } : {}),
        ...(b.shareLocation !== undefined ? { shareLocation: b.shareLocation } : {}),
      },
      { merge: true },
    );
  return { ok: true };
});

import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";
import { membersAfterLeave } from "../../social.js";

/**
 * 合流から抜ける。
 *
 * 押した人だけが外れる。以前は誰が押しても全員分を閉じていたが、
 * それだと「自分はもう行けない」と「みんなで解散」が区別できず、
 * 1人の離脱で他のメンバーの旗まで消えていた。
 *
 * 残りが1人以下になったら、合流そのものを閉じる(§membersAfterLeave)。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const { meetupId } = z.object({ meetupId: z.string() }).parse(body(req));
  const ref = db().collection(COL.meetups).doc(meetupId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpError(404, "合流が見つかりません", "not_found");
  const current: string[] = (snap.data() as any)?.memberUids ?? [];
  if (!current.includes(ctx.uid!)) throw new HttpError(403, "この合流のメンバーではありません", "forbidden");

  const { members, active } = membersAfterLeave(current, ctx.uid!);
  await ref.set(
    { memberUids: members, active, ...(active ? {} : { endedAt: FieldValue.serverTimestamp() }) },
    { merge: true },
  );
  return { ok: true, active, remaining: members.length };
});

import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";
import { assertFriend, displayNameOf, threadId } from "../../social.js";
import { pushToUsers } from "../../agent/store.js";

const Body = z.object({
  toUid: z.string(),
  text: z.string().max(500).optional(),
  /** スタンプ。text と排他。 */
  reaction: z.string().max(8).optional(),
});

/**
 * 本人が打つメッセージ／スタンプ。
 *
 * エージェントが代筆する経路(`/api/friends/message`)とは別で、**承認ゲートを
 * 通さない**。ゲートは「AI が勝手に送らないため」の仕組みであって、
 * 本人が自分の言葉で送るのを止める理由はない。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = Body.parse(body(req));
  const text = b.text?.trim();
  if (!text && !b.reaction) throw new HttpError(400, "本文もスタンプもありません", "bad_request");
  await assertFriend(ctx.uid!, b.toUid);

  const id = threadId(ctx.uid!, b.toUid);
  const ref = db().collection(COL.messages).doc(id).collection("list").doc();
  await ref.set({
    fromUid: ctx.uid!,
    ...(text ? { text } : {}),
    ...(b.reaction ? { reaction: b.reaction } : {}),
    at: FieldValue.serverTimestamp(),
  });

  const name = await displayNameOf(ctx.uid!);
  await pushToUsers([b.toUid], name, text ?? b.reaction!, { type: "message", fromUid: ctx.uid! });
  return { ok: true, messageId: ref.id, threadId: id };
});

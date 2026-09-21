import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";
import { friendUids, pushToUsers } from "../../agent/store.js";
import { getPlaceName } from "../../tools/areaCode.js";

const Body = z.object({
  lat: z.number().optional(),
  lng: z.number().optional(),
  incidentId: z.string().optional(),
  /** 災害の種別。通知文に使うだけで、判断には使わない。 */
  disaster: z.string().max(20).default("災害"),
});

/**
 * 代理通報の依頼を出す。
 *
 * **119番や自治体には繋がらない。** フレンドに「代わりに通報してほしい」と
 * 頼むだけ ── 繋がると誤解されると、通報したつもりで誰にも届いていない状態を
 * 作ってしまう。文言でもそう書く。
 *
 * 通知に載せるのは**ニックネームと市区町村**まで。本名・住所・年齢・電話は
 * 載せず、フレンドが画面で「確認する」を押して初めて emergency/{uid} を読む。
 * 通知はロック画面に出るので、そこに住所を出すわけにいかない。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = Body.parse(body(req));
  const uid = ctx.uid!;

  const emergency = await db().collection(COL.emergency).doc(uid).get();
  if (!emergency.exists) throw new HttpError(400, "緊急時情報が未登録です", "bad_request");

  const friends = await friendUids(uid);
  if (!friends.length) throw new HttpError(400, "依頼できる相手がいません", "bad_request");

  const me = (await db().collection(COL.users).doc(uid).get()).data() as any;
  const nickname = (me?.displayName as string) ?? "友だち";
  const areaName = b.lat != null && b.lng != null ? await getPlaceName({ lat: b.lat, lng: b.lng }) : null;

  const ref = db().collection(COL.sos).doc();
  await ref.set({
    uid,
    nickname,
    areaName,
    disaster: b.disaster,
    incidentId: b.incidentId ?? null,
    recipients: friends,
    active: true,
    createdAt: FieldValue.serverTimestamp(),
  });

  // 個人情報そのものは移さず、「この相手には開いてよい」だけを立てる。
  await db().collection(COL.emergency).doc(uid).set({ revealedTo: friends }, { merge: true });

  await pushToUsers(
    friends,
    "SOS: 通報の依頼が届いています",
    `${areaName ?? ""}の${b.disaster}で、${nickname}さんが被災している可能性があります`,
    { type: "sos", sosId: ref.id, uid },
  );
  return { ok: true, sosId: ref.id, sentTo: friends.length };
});

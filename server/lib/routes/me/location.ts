import { z } from "zod";
import { route, body } from "../../http.js";
import { db, COL, FieldValue, Timestamp } from "../../firebase.js";
import { getPlaceName, placeCell } from "../../tools/areaCode.js";
import { updatePlacePresence } from "../../tools/places.js";

const Body = z.object({
  lat: z.number(),
  lng: z.number(),
  /** 観測時刻。送信時刻ではない。 */
  at: z.string(),
  accuracyM: z.number().optional(),
  batteryPct: z.number().int().min(0).max(100).optional(),
});

/**
 * 最後にいた場所を受け取って `locations/{uid}` に置く。
 *
 * 圏外で溜めた分がまとめて届くので、**到着順ではなく `at` の新しい方**を残す。
 * 古い位置で上書きすると「さっきまでここにいた」が巻き戻り、捜す側が誤解する。
 *
 * 読めるのは本人と、本人が相手ごとに許可したフレンドだけ(Firestore ルール)。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = Body.parse(body(req));
  const at = new Date(b.at);
  if (Number.isNaN(at.getTime())) throw new Error("at is not a date");

  const ref = db().collection(COL.locations).doc(ctx.uid!);
  const prev = (await ref.get()).data() as any;
  const prevAt: Date | undefined = prev?.at?.toDate?.();
  if (prevAt && prevAt.getTime() >= at.getTime()) return { ok: true, applied: false, reason: "older" };

  // 座標そのものは端末に出さない。フレンドに見せるのは区市町村まで(設計書 §119)。
  // 同じ升目に留まっている間は引き直さない ── 位置は 50m 動くたびに届くので、
  // 毎回引くと同じ区名を1日に何百回も取りに行くことになる。
  const cell = placeCell(b);
  const areaName = prev?.areaCell === cell && prev?.areaName ? (prev.areaName as string) : await getPlaceName(b);

  await ref.set(
    {
      lat: b.lat,
      lng: b.lng,
      at: Timestamp.fromDate(at),
      areaCell: cell,
      ...(b.accuracyM != null ? { accuracyM: b.accuracyM } : {}),
      ...(b.batteryPct != null ? { batteryPct: b.batteryPct } : {}),
      ...(areaName ? { areaName } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  // 登録した場所への出入りはここで見る。端末が寝ている間の到着こそ知りたいので、
  // クライアント判定にはしない。失敗しても位置の記録は成立させる。
  try {
    await updatePlacePresence(ctx.uid!, b, at);
  } catch (e) {
    console.warn("[places] presence update failed", e);
  }

  return { ok: true, applied: true, areaName };
});

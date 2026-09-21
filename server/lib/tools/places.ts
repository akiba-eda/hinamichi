import { db, COL, FieldValue } from "../firebase.js";
import { haversineM, type LatLng } from "../geo.js";
import { friendUids, pushToUsers } from "../agent/store.js";
import { displayNameOf } from "../social.js";

/**
 * 登録した場所への出入りを判定して、変わったときだけ記録する。
 *
 * **端末側では判定しない。** 画面を開いていない・寝ている間の到着こそ
 * 知りたいので、位置が届いた時にサーバーで見る。
 *
 * 境界を跨ぐたびに通知が往復しないよう、出るときの輪は入るときより広く取る
 * (ヒステリシス)。測位は数十m揺れるので、同じ半径で出入りを判定すると
 * 家の中にいるだけで「着いた/出た」を繰り返す。
 */
const LEAVE_MARGIN = 1.35;

export async function updatePlacePresence(uid: string, p: LatLng, at: Date) {
  const places = await db().collection(COL.places).doc(uid).collection("list").get();
  if (places.empty) return;

  const stateRef = db().collection(COL.places).doc(uid);
  const inside: string[] = ((await stateRef.get()).data() as any)?.inside ?? [];
  const next: string[] = [];
  const changed: Array<{ name: string; arrived: boolean }> = [];

  for (const d of places.docs) {
    const v = d.data() as any;
    if (typeof v.lat !== "number" || typeof v.lng !== "number") continue;
    const dist = haversineM(p, { lat: v.lat, lng: v.lng });
    const r = (v.radiusM as number) ?? 150;
    const was = inside.includes(d.id);
    const now = was ? dist <= r * LEAVE_MARGIN : dist <= r;
    if (now) next.push(d.id);
    if (now !== was) changed.push({ name: (v.name as string) ?? "場所", arrived: now });
  }

  if (!changed.length) {
    // 出入りが変わっていなければ書かない。位置は何度も届くので、
    // 毎回書くと履歴が同じ内容で埋まる。
    if (next.length !== inside.length) await stateRef.set({ inside: next }, { merge: true });
    return;
  }

  const name = await displayNameOf(uid);
  const events = db().collection(COL.placeEvents).doc(uid).collection("list");
  const batch = db().batch();
  batch.set(stateRef, { inside: next }, { merge: true });
  for (const c of changed) {
    batch.set(events.doc(), { placeName: c.name, arrived: c.arrived, at, createdAt: FieldValue.serverTimestamp() });
  }
  await batch.commit();

  // 到着だけ通知する。出発まで鳴らすと多すぎて読まれなくなる。
  const arrivals = changed.filter((c) => c.arrived);
  if (!arrivals.length) return;
  const friends = await friendUids(uid);
  for (const a of arrivals) {
    await pushToUsers(friends, "ヒナミチ", `${name}さんが${a.name}に着きました`, { type: "place", uid, arrived: "1" });
  }
}

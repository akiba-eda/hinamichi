import { z } from "zod";
import { route, body } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";
import { assertFriend, displayNameOf, membersAfterLeave } from "../../social.js";
import { pushToUsers } from "../../agent/store.js";

const Body = z.object({
  name: z.string().min(1).max(30),
  lat: z.number(),
  lng: z.number(),
  memberUids: z.array(z.string()).min(1).max(20),
  /** 災害から作られた合流か。画面の色と文言が変わる。 */
  fromIncident: z.boolean().default(false),
});

/** 合流を始める。平時は待ち合わせ、災害時は「どの避難場所で落ち合うか」。 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = Body.parse(body(req));
  // 友だちでない相手を巻き込めないようにする。
  const others = b.memberUids.filter((u) => u !== ctx.uid);
  await Promise.all(others.map((u) => assertFriend(ctx.uid!, u)));

  // 参加できる合流は1人につき1つに保つ。アプリは常に1件しか出せないので、
  // 古いものを残すと新しい合流が隠れ、隠れた方は閉じる手段が無くなる。
  await leaveAllActive(ctx.uid!);

  const ref = db().collection(COL.meetups).doc();
  await ref.set({
    name: b.name,
    lat: b.lat,
    lng: b.lng,
    // 作った本人は必ず入れる。抜けていると自分の画面に出ない。
    memberUids: Array.from(new Set([ctx.uid!, ...b.memberUids])),
    ownerUid: ctx.uid!,
    fromIncident: b.fromIncident,
    active: true,
    createdAt: FieldValue.serverTimestamp(),
  });

  const name = await displayNameOf(ctx.uid!);
  await pushToUsers(others, "ヒナミチ", `${name}さんが「${b.name}」で合流しようとしています`, { type: "meetup", meetupId: ref.id });
  return { ok: true, meetupId: ref.id };
});

/** 自分が入っている active な合流から、自分だけ抜けておく。 */
async function leaveAllActive(uid: string) {
  const q = await db().collection(COL.meetups).where("memberUids", "array-contains", uid).where("active", "==", true).get();
  if (q.empty) return;
  const batch = db().batch();
  for (const d of q.docs) {
    const { members, active } = membersAfterLeave(((d.data() as any)?.memberUids ?? []) as string[], uid);
    batch.set(d.ref, { memberUids: members, active, ...(active ? {} : { endedAt: FieldValue.serverTimestamp() }) }, { merge: true });
  }
  await batch.commit();
}

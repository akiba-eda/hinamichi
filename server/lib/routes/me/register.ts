import { z } from "zod";
import { route, body } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";
import { cardOf, fanOutProfile } from "../../profile.js";

const Body = z.object({
  displayName: z.string().min(1).max(30).optional(),
  fcmToken: z.string().optional(),
  platform: z.enum(["android", "ios", "web"]).optional(),
  /** 256px まで縮めた JPEG の base64。空文字は「消す」。Storage は使わない(設計書 §119)。 */
  avatarImage: z.string().max(400_000).optional(),
  /** セナヴィの表情から選んだ場合の識別子。 */
  avatarMood: z.string().max(20).optional(),
  consent: z.object({ shareStatusWithFriends: z.boolean().optional(), shareShelterName: z.boolean().optional(), shareRawLocation: z.literal(false).optional() }).optional(),
});

/** Upsert the caller's profile. Creates an invite code on first call. */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = Body.parse(body(req));
  const ref = db().collection(COL.users).doc(ctx.uid!);
  const snap = await ref.get();
  const inviteCode = (snap.data() as any)?.inviteCode ?? genCode();
  await ref.set(
    {
      displayName: b.displayName ?? (snap.data() as any)?.displayName ?? "わたし",
      ...(b.fcmToken ? { fcmToken: b.fcmToken } : {}),
      ...(b.platform ? { platform: b.platform } : {}),
      ...(b.consent ? { consent: { ...((snap.data() as any)?.consent ?? { shareStatusWithFriends: true, shareShelterName: true, shareRawLocation: false }), ...b.consent } } : {}),
      // 画像を選べば表情は消え、表情を選べば画像は消える。両方は持たない。
      ...(b.avatarImage !== undefined ? { avatarImage: b.avatarImage || null, avatarMood: b.avatarImage ? null : ((snap.data() as any)?.avatarMood ?? null) } : {}),
      ...(b.avatarMood !== undefined ? { avatarMood: b.avatarMood || null, avatarImage: b.avatarMood ? null : ((snap.data() as any)?.avatarImage ?? null) } : {}),
      inviteCode,
      updatedAt: FieldValue.serverTimestamp(),
      ...(snap.exists ? {} : { createdAt: FieldValue.serverTimestamp(), consent: { shareStatusWithFriends: true, shareShelterName: true, shareRawLocation: false } }),
    },
    { merge: true },
  );
  await db().collection(COL.statuses).doc(ctx.uid!).set({ state: "safe", updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  // 表示名かアイコンが変わったら、フレンドの一覧に写してある分を配り直す。
  if (b.displayName !== undefined || b.avatarImage !== undefined || b.avatarMood !== undefined) {
    await fanOutProfile(ctx.uid!, cardOf((await ref.get()).data()));
  }
  return { uid: ctx.uid, inviteCode };
});

function genCode() {
  const s = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 6 }, () => s[Math.floor(Math.random() * s.length)]).join("");
}

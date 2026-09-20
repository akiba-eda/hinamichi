import { z } from "zod";
import { route, body } from "../../lib/http.js";
import { db, COL, FieldValue } from "../../lib/firebase.js";

const Body = z.object({
  displayName: z.string().min(1).max(30).optional(),
  fcmToken: z.string().optional(),
  platform: z.enum(["android", "ios", "web"]).optional(),
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
      inviteCode,
      updatedAt: FieldValue.serverTimestamp(),
      ...(snap.exists ? {} : { createdAt: FieldValue.serverTimestamp(), consent: { shareStatusWithFriends: true, shareShelterName: true, shareRawLocation: false } }),
    },
    { merge: true },
  );
  await db().collection(COL.statuses).doc(ctx.uid!).set({ state: "safe", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { uid: ctx.uid, inviteCode };
});

function genCode() {
  const s = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 6 }, () => s[Math.floor(Math.random() * s.length)]).join("");
}

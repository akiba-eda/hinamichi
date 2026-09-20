import { z } from "zod";
import { route, body, requireDemoAdmin } from "../../http.js";
import { setCrowdFull } from "../../tools/crowd.js";
import { db, COL } from "../../firebase.js";
import { reselect } from "../../agent/service.js";

/** Demo: mark a shelter full (or relieve it) and re-route the caller's active incident if affected. */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  requireDemoAdmin(ctx.uid!);
  const b = z.object({ shelterId: z.string(), full: z.boolean().default(true), lat: z.number(), lng: z.number(), locationSource: z.enum(["gps", "cached", "override"]).default("gps") }).parse(body(req));
  await setCrowdFull(b.shelterId, b.full);
  if (!b.full) return { ok: true };
  const q = await db().collection(COL.incidents).where("uid", "==", ctx.uid!).where("shelter.id", "==", b.shelterId).where("state", "in", ["proposing", "guiding", "fallback_guiding"]).limit(1).get();
  if (q.empty) return { ok: true, rerouted: false };
  const result = await reselect({ uid: ctx.uid!, incidentId: q.docs[0]!.id, location: b, locationSource: b.locationSource, reason: "crowd" });
  return { ok: true, rerouted: true, incidentId: q.docs[0]!.id, ...result };
});

import { z } from "zod";
import { assertQuota, QUOTA } from "../../quota.js";
import { route, body } from "../../http.js";
import { LocationBody, reselect } from "../../agent/service.js";

export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  await assertQuota(ctx.uid!, "reselect", QUOTA.reselect);
  const b = LocationBody.extend({ incidentId: z.string(), reason: z.enum(["crowd", "user", "alert", "route"]).default("user"), demo: z.object({ failLlm: z.boolean().optional() }).optional() }).parse(body(req));
  const result = await reselect({ uid: ctx.uid!, incidentId: b.incidentId, location: { lat: b.lat, lng: b.lng }, locationSource: b.locationSource, reason: b.reason, demo: b.demo });
  return { incidentId: b.incidentId, ...result };
});

import { z } from "zod";
import { route, body } from "../../lib/http.js";
import { LocationBody, startIncident } from "../../lib/agent/service.js";

/** Start (or resume) the agent for an alert. Called when the app opens from a push. */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = LocationBody.extend({ alertId: z.string(), force: z.boolean().optional(), demo: z.object({ failLlm: z.boolean().optional() }).optional() }).parse(body(req));
  const { incidentId, result, reused } = await startIncident({ uid: ctx.uid!, alertId: b.alertId, location: { lat: b.lat, lng: b.lng }, locationSource: b.locationSource, demo: b.demo, force: b.force });
  return { incidentId, reused, ...result };
});

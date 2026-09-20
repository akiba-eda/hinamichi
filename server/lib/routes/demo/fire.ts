import { z } from "zod";
import { route, body, requireDemoAdmin } from "../../http.js";
import { createDemoAlert, deliverDemoAlert } from "../../alerts.js";
import { startIncident } from "../../agent/service.js";

/**
 * Demo: fire a disaster anchored at the caller's current location, push to the caller's devices,
 * and (optionally) run the agent right away so the incident exists even if the push is slow.
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  requireDemoAdmin(ctx.uid!);
  const b = z.object({
    scenario: z.enum(["earthquake", "heavy_rain", "tsunami"]),
    lat: z.number(), lng: z.number(),
    locationSource: z.enum(["gps", "cached", "override"]).default("gps"),
    runNow: z.boolean().default(true),
    demo: z.object({ failLlm: z.boolean().optional() }).optional(),
  }).parse(body(req));
  const alert = await createDemoAlert(ctx.uid!, b.scenario, b);
  await deliverDemoAlert(alert, ctx.uid!);
  if (!b.runNow) return { alertId: alert.id, title: alert.title };
  const { incidentId, result } = await startIncident({ uid: ctx.uid!, alertId: alert.id, location: b, locationSource: b.locationSource, demo: b.demo, force: true });
  return { alertId: alert.id, title: alert.title, incidentId, ...result };
});

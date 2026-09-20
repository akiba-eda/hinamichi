import { z } from "zod";
import { route, body } from "../../http.js";
import { updatePosition } from "../../agent/service.js";

/** Periodic position while guiding → arrival geofence. Coordinates are not persisted. */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = z.object({ incidentId: z.string(), lat: z.number(), lng: z.number() }).parse(body(req));
  return updatePosition(ctx.uid!, b.incidentId, b);
});

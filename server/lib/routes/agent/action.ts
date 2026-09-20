import { z } from "zod";
import { route, body } from "../../http.js";
import { applyAction } from "../../agent/service.js";

/** Human gate + lifecycle: start (approve) / later / arrived / safe_zone / close. */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = z.object({ incidentId: z.string(), action: z.enum(["start", "later", "arrived", "safe_zone", "close"]), via: z.enum(["user", "timeout"]).default("user") }).parse(body(req));
  return applyAction(ctx.uid!, b.incidentId, b.action, b.via);
});

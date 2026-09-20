import { route } from "../../lib/http.js";
import { broadcastAlert, pollQuakes, pollWarnings } from "../../lib/alerts.js";

/**
 * Called by cron-job.org every 2 minutes: GET /api/watch/disasters?token=...
 * Polls P2P地震情報 + 気象庁 warnings; new events become alerts and are pushed to topic "all".
 */
export default route({ methods: ["GET", "POST"], auth: "cron" }, async () => {
  const results = await Promise.allSettled([pollQuakes(), pollWarnings()]);
  const created = results.flatMap((r) => (r.status === "fulfilled" ? r.value : []));
  const errors = results.filter((r): r is PromiseRejectedResult => r.status === "rejected").map((r) => String(r.reason?.message ?? r.reason));
  for (const a of created) await broadcastAlert(a);
  return { created: created.map((a) => ({ id: a.id, type: a.type, title: a.title })), errors, at: new Date().toISOString() };
});

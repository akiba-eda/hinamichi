import { z } from "zod";
import { route, body } from "../../lib/http.js";
import { orcaChat } from "../../lib/orca.js";
import { notifyFriends, IncidentLog } from "../../lib/agent/store.js";
import { db, COL } from "../../lib/firebase.js";

/**
 * Human-approved free-text message to friends (ApprovalSheet).
 * The text passes through OrcaRouter (triage tier) so the PII Guardrail attached to the key
 * masks phone numbers / emails before any model sees it, and we forward the *masked* text.
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const { text, incidentId } = z.object({ text: z.string().min(1).max(200), incidentId: z.string().optional() }).parse(body(req));
  let outgoing = text;
  let meta: Record<string, unknown> = {};
  try {
    const { data, meta: m } = await orcaChat({
      tier: "triage", sessionId: incidentId ?? `msg_${ctx.uid}`, promptName: "hina-message-system",
      systemFallback: "あなたは防災アプリのメッセージ整形係です。ユーザーの文をそのまま、40字以内で丁寧語に整えて返してください。内容を足さないでください。返答は整形後の文だけ。",
      messages: [{ role: "user", content: text }], timeoutMs: 6000, temperature: 0,
    });
    const polished = data.choices[0]?.message?.content?.trim();
    if (polished) outgoing = polished.slice(0, 80);
    meta = { model: m.resolvedModel, costUsd: m.costUsd, promptRef: m.promptRef };
  } catch {
    /* guardrail block (HTTP 400) or timeout → send original text unchanged */
  }
  const me = (await db().collection(COL.users).doc(ctx.uid!).get()).data() as any;
  const n = await notifyFriends(ctx.uid!, `${me?.displayName ?? "友だち"}さんから`, outgoing, { type: "message" });
  if (incidentId) {
    const log = new IncidentLog(incidentId);
    log.add({ kind: "approval", audience: "both", title: `承認済みメッセージを${n}人に送信しました`, detail: outgoing, payload: meta });
    await log.flush();
  }
  return { sent: n, text: outgoing };
});

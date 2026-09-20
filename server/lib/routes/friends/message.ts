import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { orcaChat } from "../../orca.js";
import { notifyFriends, IncidentLog } from "../../agent/store.js";
import { db, COL } from "../../firebase.js";

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
  } catch (e: any) {
    const code = e?.error?.code ?? e?.code ?? e?.error?.error?.code;
    const msg = String(e?.message ?? "");
    if (e?.status === 400 && (code === "guardrail_blocked" || /guardrail/i.test(msg))) {
      // OrcaRouter Guardrail blocked the text (e.g. credit card number). Never forward raw.
      if (incidentId) {
        const log = new IncidentLog(incidentId);
        log.add({ kind: "approval", audience: "both", title: "メッセージは送信されませんでした(ガードレールがブロック)", detail: "カード番号など送ってはいけない情報が含まれていたため、OrcaRouter Guardrail が送信前に止めました" });
        await log.flush();
      }
      throw new HttpError(400, "送信できません: 送ってはいけない情報(カード番号など)が含まれています", "guardrail_blocked");
    }
    /* timeout / provider error → send original text unchanged (guardrail did not object) */
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

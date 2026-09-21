import { z } from "zod";
import { assertQuota, QUOTA } from "../../quota.js";
import { route, body, HttpError } from "../../http.js";
import { orcaChat } from "../../orca.js";
import { notifyFriends, IncidentLog } from "../../agent/store.js";
import { db, COL } from "../../firebase.js";

/**
 * 承認カードから送る自由文(本人が書いた文を AI が丁寧語に整える)。
 *
 * OrcaRouter の triage 経路を通すので、キーに付けた PII Guardrail が
 * **モデルに届く前に**電話番号やメールを伏せ字へ置き換える。
 *
 * 伏せ字が返ってきた場合は整形をあきらめ、本人の原文をそのまま家族へ送る。
 * 守りたいのは「上流のモデル提供者に連絡先を渡さないこと」であって、
 * 家族に連絡先が届かないことではない ── 災害時にそれをやると本末転倒になる。
 * カード番号だけは block にしてあり、その時は送信そのものを止める。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  await assertQuota(ctx.uid!, "message", QUOTA.message);
  const { text, incidentId } = z.object({ text: z.string().min(1).max(200), incidentId: z.string().optional() }).parse(body(req));
  let outgoing = text;
  let meta: Record<string, unknown> = {};
  /** ガードレールが伏せた項目。何が起きたかを記録に残すために拾う。 */
  let masked: string[] = [];
  try {
    const { data, meta: m } = await orcaChat({
      tier: "triage", sessionId: incidentId ?? `msg_${ctx.uid}`, promptName: "hina-message-system",
      systemFallback: "あなたは防災アプリのメッセージ整形係です。ユーザーの文をそのまま、40字以内で丁寧語に整えて返してください。内容を足さないでください。返答は整形後の文だけ。",
      messages: [{ role: "user", content: text }], timeoutMs: 6000, temperature: 0,
    });
    const polished = data.choices[0]?.message?.content?.trim();
    meta = { model: m.resolvedModel, costUsd: m.costUsd, promptRef: m.promptRef };
    masked = maskedEntities(polished ?? "");
    // 伏せ字が返ってきたら整形をあきらめ、本人が書いた文をそのまま送る。
    // ガードレールの目的は「上流のモデルに連絡先を渡さない」ことであって、
    // 家族に番号を届けないことではない。災害時に「連絡先は090-…」が
    // [PHONE] になって届くのは、丁寧語に直る利益より遥かに大きい損。
    if (polished && !masked.length) outgoing = polished.slice(0, 80);
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
    if (masked.length) {
      log.add({
        kind: "approval",
        audience: "both",
        title: `${masked.join("・")}はモデルに渡していません`,
        detail: "OrcaRouter Guardrail が送信前に伏せ字へ置き換えたため、上流のモデルは元の値を見ていません。整形はやめて、本人が書いた文をそのまま家族へ送ります",
      });
    }
    log.add({ kind: "approval", audience: "both", title: `承認済みメッセージを${n}人に送信しました`, detail: outgoing, payload: meta });
    await log.flush();
  }
  return { sent: n, text: outgoing };
});

/**
 * 伏せ字のタグから、何が伏せられたかを読む。
 *
 * Guardrail は mask のとき `[EMAIL]` `[PHONE]` のような型付きのタグに
 * 置き換える。出てきたタグを数えれば、上流で何が止められたか分かる。
 */
const MASK_TAGS: Record<string, string> = {
  EMAIL: "メールアドレス",
  PHONE: "電話番号",
  CREDIT_CARD: "カード番号",
  SSN: "個人番号",
  IP: "IPアドレス",
  IBAN: "口座番号",
};

export function maskedEntities(text: string): string[] {
  const found = new Set<string>();
  for (const m of text.matchAll(/\[([A-Z_]+)\]/g)) {
    const label = MASK_TAGS[m[1]!];
    if (label) found.add(label);
  }
  return [...found];
}

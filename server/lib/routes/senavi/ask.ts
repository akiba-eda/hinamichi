import { z } from "zod";
import { route, body } from "../../http.js";
import { orcaChat } from "../../orca.js";
import { ASK_SYSTEM } from "../../agent/prompts.js";
import { assertNoCoordinates } from "../../agent/abstraction.js";
import { getOutlook, getRainNowcast } from "../../tools/weather.js";
import { getHazard } from "../../tools/hazard.js";

const Body = z.object({
  question: z.string().min(1).max(100),
  lat: z.number(),
  lng: z.number(),
});

/**
 * 平時の問いかけに答える。「今日雨降る？」「傘いる？」など。
 *
 * **座標は LLM に渡さない。** 緯度経度はこのサーバーの中だけで使い、
 * 天気や地名という「答え」に変換してから渡す。災害時の判断経路
 * (agent/loop.ts)と同じ規律で、同じ `assertNoCoordinates` が守る。
 *
 * 答えられる材料は 0〜60分のレーダーと今日・明日の府県予報だけ。
 * それ以外を聞かれたら「分からない」と言わせる(ASK_SYSTEM)。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = Body.parse(body(req));
  const here = { lat: b.lat, lng: b.lng };

  const [rain, outlook, hazard] = await Promise.all([
    getRainNowcast(here),
    getOutlook(here),
    getHazard(here).catch(() => null),
  ]);

  const facts = {
    areaName: outlook?.areaName ?? null,
    いまの雨: {
      降水強度mmh: rain.nowMmh,
      これから60分の最大mmh: rain.maxMmh,
      何分後に降り出すか: rain.startsInMin,
      何分後にやむか: rain.stopsInMin,
    },
    今日の予報: outlook?.today ?? null,
    明日の予報: outlook?.tomorrow ?? null,
    この場所のハザード: hazard
      ? { 浸水想定: hazard.floodLabel, 津波想定: hazard.tsunami > 0, 土砂警戒区域: hazard.landslide }
      : null,
  };
  assertNoCoordinates(facts);

  const { data, meta } = await orcaChat({
    tier: "triage",
    // セッションIDは HTTP ヘッダに載るので ASCII だけ。地名を入れると落ちる。
    sessionId: `ask_${ctx.uid}`,
    promptName: "hina-ask-system",
    systemFallback: ASK_SYSTEM,
    messages: [
      { role: "user", content: `わかっている事実:\n${JSON.stringify(facts, null, 1)}\n\n質問: ${b.question}` },
    ],
    timeoutMs: 12000,
    temperature: 0.3,
  });

  const answer = data.choices[0]?.message?.content?.trim();
  return {
    answer: answer || "うまく調べられなかった。もう一度聞いてみて",
    model: meta.resolvedModel,
    costUsd: meta.costUsd,
  };
});

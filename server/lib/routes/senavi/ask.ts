import { z } from "zod";
import { assertQuota, QUOTA } from "../../quota.js";
import { route, body } from "../../http.js";
import { orcaChat } from "../../orca.js";
import { ASK_SYSTEM } from "../../agent/prompts.js";
import { assertNoCoordinates } from "../../agent/abstraction.js";
import { getOutlook, getRainNowcast } from "../../tools/weather.js";
import { getHazard } from "../../tools/hazard.js";
import { listShelters } from "../../tools/shelters.js";
import { getPlaceName } from "../../tools/areaCode.js";

/**
 * セナヴィが答えられること。**ここに無い問いには答えない。**
 *
 * 自由に喋らせると、LLM は実在するドメインの下に存在しないパスを書く。
 * 実際に試したところ、避難場所を尋ねた回答に付いてきた自治体の URL は
 * 4本中4本が 404 だった(2026-09-22 実測)。本物らしく見えるぶん質が悪い。
 *
 * なので答えられる範囲を先に決めて、材料も出典もこちらが用意する。
 * LLM の仕事は、用意した事実をセナヴィの口調に直すことだけ。
 */
export const COMMANDS = {
  weather: { label: "今日の天気は？" },
  hazard: { label: "ここは安全？" },
  shelters: { label: "近くの避難場所は？" },
  rain: { label: "いま雨降ってる？" },
} as const;
export type Command = keyof typeof COMMANDS;

/**
 * 出典。**実在を確認したものだけを置く。**
 * 増やすときは必ず叩いて 200 を確かめること(404 の出典は嘘と同じ)。
 */
const SOURCES = {
  nowcast: { name: "気象庁 高解像度降水ナウキャスト", url: "https://www.jma.go.jp/bosai/nowc/" },
  forecast: { name: "気象庁 天気予報", url: "https://www.jma.go.jp/bosai/forecast/" },
  hazard: { name: "ハザードマップポータルサイト(国土交通省)", url: "https://disaportal.gsi.go.jp/" },
  shelters: { name: "指定緊急避難場所データ(国土地理院)", url: "https://www.gsi.go.jp/bousaichiri/hinanbasho.html" },
} as const;

const Body = z.object({
  command: z.enum(["weather", "hazard", "shelters", "rain"]),
  lat: z.number(),
  lng: z.number(),
});

export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  await assertQuota(ctx.uid!, "ask", QUOTA.ask);
  const b = Body.parse(body(req));
  const here = { lat: b.lat, lng: b.lng };

  let facts: Record<string, unknown> = {};
  let sources: Array<{ name: string; url: string }> = [];

  if (b.command === "weather" || b.command === "rain") {
    const [rain, outlook] = await Promise.all([getRainNowcast(here), getOutlook(here)]);
    // 「今日」ではなく日付そのものを渡す。キー名に「今日」と書くと、
    // モデルがそのまま「今日」と答えてしまい、いつの話か伝わらない。
    const now = new Date();
    facts = {
      いまの日時: `${now.getMonth() + 1}/${now.getDate()} ${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`,
      地名: outlook?.areaName ?? null,
      いまの降水強度mmh: rain.nowMmh,
      これから60分の最大mmh: rain.maxMmh,
      何分後に降り出すか: rain.startsInMin,
      何分後にやむか: rain.stopsInMin,
      ...(b.command === "weather"
        ? {
            [`${outlook?.today?.date ?? "この日"}の予報`]: outlook?.today
              ? { 天気: outlook.today.text, 降水確率: outlook.today.pops }
              : null,
            [`${outlook?.tomorrow?.date ?? "翌日"}の予報`]: outlook?.tomorrow?.text ?? null,
          }
        : {}),
    };
    sources = b.command === "weather" ? [SOURCES.nowcast, SOURCES.forecast] : [SOURCES.nowcast];
  } else if (b.command === "hazard") {
    const [hz, name] = await Promise.all([getHazard(here), getPlaceName(here)]);
    facts = {
      地名: name,
      浸水想定: hz.floodLabel,
      津波想定: hz.tsunami > 0 ? "あり" : "なし",
      土砂災害警戒区域: hz.landslide,
    };
    sources = [SOURCES.hazard];
  } else {
    const [list, name] = await Promise.all([
      listShelters(here, "earthquake", { limit: 3 }),
      getPlaceName(here),
    ]);
    facts = {
      地名: name,
      // 件数を数えて渡す。数えさせると 3 件を「どちらも」と書いてしまう。
      件数: list.length,
      近い順の避難場所: list.map((s) => ({
        名前: s.name,
        徒歩分: s.walkMin,
        距離m: s.distanceM,
        方角: s.direction,
        標高m: s.elevationM,
        浸水想定: s.hazard?.floodLabel,
      })),
    };
    sources = [SOURCES.shelters, SOURCES.hazard];
  }

  assertNoCoordinates(facts);

  const { data, meta } = await orcaChat({
    tier: "triage",
    sessionId: `ask_${ctx.uid}`,
    promptName: "hina-ask-system",
    systemFallback: ASK_SYSTEM,
    messages: [
      {
        role: "user",
        content: `質問: ${COMMANDS[b.command].label}\n\nわかっている事実:\n${JSON.stringify(facts, null, 1)}`,
      },
    ],
    timeoutMs: 12000,
    temperature: 0.3,
  });

  const raw = data.choices[0]?.message?.content?.trim();
  return {
    answer: raw ? fixDates(fixCounting(raw, (facts as any).件数)) : "うまく調べられなかった。もう一度押してみて",
    // 出典は LLM に言わせない。こちらが用意したものをそのまま返す。
    sources,
    model: meta.resolvedModel,
    costUsd: meta.costUsd,
  };
});

/**
 * 「どちらも」を件数に合わせて直す。
 *
 * プロンプトで「2件のときだけ」と書いても、軽いモデルは 3 件でも「どちらも」と
 * 書いてくる(実測で3回中3回)。指示で直らないものは出力側で直す ── 仮名 A〜H を
 * 「ここ」に直しているのと同じ考え方。
 */
export function fixCounting(text: string, count?: number): string {
  if (typeof count !== "number" || count === 2) return text;
  const word = count >= 3 ? `${count}件とも` : "";
  return text.replace(/どちらも|両方とも|どちらの[^、。]*?も/g, word || "");
}

/**
 * 「今日」「明日」を日付に直す。
 *
 * 押したボタンに「今日の天気は？」と書いてあるので、モデルはそれをなぞって
 * 「今日の天気は」と返す(実測で5回中2回)。**相対表現は、あとから画面を
 * 見返したときにいつの話か分からなくなる。** スクリーンショットを家族に
 * 送ったときも同じことが起きる。
 */
export function fixDates(text: string, now = new Date()): string {
  const md = (offset: number) => {
    const d = new Date(now);
    d.setDate(d.getDate() + offset);
    return `${d.getMonth() + 1}/${d.getDate()}`;
  };
  return text
    .replace(/明後日/g, md(2))
    .replace(/明日|あした|あす/g, md(1))
    .replace(/今日|本日|きょう/g, md(0));
}

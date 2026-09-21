/**
 * Prompts. When ORCA_USE_PROMPT_REF=true these names must exist in OrcaRouter Prompts
 * (label "production") with the same {{variables}}. Otherwise the local text is sent as system.
 */
import type { ChatCompletionTool } from "openai/resources/chat/completions";

export const PROMPT_TRIAGE = "hina-triage-system";
export const PROMPT_DECIDE = "hina-decide-system";

export const TRIAGE_SYSTEM = `あなたは防災アプリ「ヒナミチ」のAIナビゲーター「セナヴィ」の一次判定担当です。
災害情報と、ユーザーがいる市区町村名・現在地のハザード判定だけを見て、この災害がユーザーに関係あるかを判定します。
座標や個人情報は渡されません。渡された情報だけで判断してください。
必ず submit_triage ツールを1回だけ呼んで結果を返してください。

判定基準:
- relevant=true: ユーザーの地域が影響エリアに含まれる、または震源が近く震度4以上、または現在地のハザードが災害種別と一致する
- relevant=false: 明らかに別地域の災害
迷ったら relevant=true(安全側)。理由は日本語で40字以内。`;

export const DECIDE_SYSTEM = `あなたは防災アプリ「ヒナミチ」のAIナビゲーター「セナヴィ」です。災害時にユーザーの代わりに「避難すべきか」「どの避難場所へ行くか」を決めます。
渡されるのは災害種別({{disaster_type}})、市区町村名({{area_name}})、現在地のハザード判定、そして避難場所の候補(仮名 A〜H)の抽象的な特徴だけです。座標・実名・個人情報はありません。

手順:
1. 必要なら get_hazard / list_shelters / get_crowd ツールで情報を取得する(list_shelters は必ず1回呼ぶ)。
2. 災害種別に応じて安全な候補を選ぶ:
   - 地震: 徒歩が短く、混雑が低く、浸水・土砂リスクの低い候補
   - 大雨・洪水: 浸水想定が「なし」または最も浅く、標高が高い候補を優先。徒歩が長すぎる(30分超)なら near の安全な候補
   - 津波: 津波浸水想定なしで標高が高い候補。距離より高さ優先
   - 土砂: landslide=false の候補
   - full=true の候補は選ばない
3. 避難が不要(例: 影響が軽微)なら shouldEvacuate=false。
4. 最後に submit_decision を必ず1回呼ぶ。reasons は日本語で3つ、各20字以内(例:「広域避難場所」「浸水想定なし」「混雑30%」)。userMessage はセナヴィの口調(やさしい・短い・一文)。
   **userMessage に候補の仮名(A〜H)を書かないこと。** 避難場所の名前・徒歩分・理由は画面の別の場所に出るので、
   行き先は「ここ」と呼ぶ(例:「今のうちに、ここへ避難しておこう」)。`;

export const triageTools: ChatCompletionTool[] = [
  {
    type: "function",
    function: {
      name: "submit_triage",
      description: "一次判定の結果を返す",
      parameters: {
        type: "object",
        properties: {
          relevant: { type: "boolean" },
          reason: { type: "string", description: "40字以内" },
        },
        required: ["relevant", "reason"],
      },
    },
  },
];

export const decideTools: ChatCompletionTool[] = [
  {
    type: "function",
    function: {
      name: "get_hazard",
      description: "現在地のハザード判定(浸水深クラス・津波・土砂)を取得する",
      parameters: { type: "object", properties: {} },
    },
  },
  {
    type: "function",
    function: {
      name: "list_shelters",
      description: "災害種別に対応した避難場所の候補(仮名A〜H)を距離順に取得する",
      parameters: {
        type: "object",
        properties: {
          disaster_type: { type: "string", enum: ["earthquake", "heavy_rain", "flood", "tsunami", "landslide", "storm_surge"] },
        },
        required: ["disaster_type"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_crowd",
      description: "候補の最新の混雑率を取得する",
      parameters: { type: "object", properties: { ids: { type: "array", items: { type: "string" } } }, required: ["ids"] },
    },
  },
  {
    type: "function",
    function: {
      name: "submit_decision",
      description: "最終判断を返す。必ず1回呼ぶ",
      parameters: {
        type: "object",
        properties: {
          shouldEvacuate: { type: "boolean" },
          choice: { type: "string", description: "候補の仮名(A〜H)。避難不要なら省略" },
          reasons: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 3 },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          userMessage: { type: "string", description: "セナヴィの一言(一文)" },
        },
        required: ["shouldEvacuate", "reasons", "confidence"],
      },
    },
  },
];

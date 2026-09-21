/**
 * The agent loop. One incident = one alert × one user.
 *   triage (cheap tier) → tool-calling decision (quality tier) → SafetyValidator
 *   → (escalate once on rejection) → fallback → route → persist → publish status → notify friends.
 * Raw coordinates live only in this function's scope.
 */
import type { ChatCompletionMessageParam } from "openai/resources/chat/completions";
import { orcaChat, type OrcaMeta } from "../orca.js";
import { getAreaCode, type AreaInfo } from "../tools/areaCode.js";
import { getHazard, TileCache, type Hazard } from "../tools/hazard.js";
import { listShelters, type DisasterType } from "../tools/shelters.js";
import { getCrowd, adjustCrowd } from "../tools/crowd.js";
import { getRoute } from "../tools/route.js";
import { walkMinutes, type LatLng } from "../geo.js";
import { abstractCandidates, assertNoCoordinates, buildCandidates, deanonymise } from "./abstraction.js";
import { DECIDE_SYSTEM, PROMPT_DECIDE, PROMPT_TRIAGE, TRIAGE_SYSTEM, decideTools, triageTools } from "./prompts.js";
import { validateLetter } from "./validator.js";
import { reasonsFor, ruleBasedSelect } from "./fallback.js";
import { IncidentLog, notifyFriends, publishStatus, setIncident } from "./store.js";
import type { AlertDoc, CandidateCtx, Decision, IncidentState, LocationSource } from "./types.js";

export type RunInput = {
  uid: string;
  incidentId: string;
  alert: AlertDoc;
  location: LatLng;
  locationSource: LocationSource;
  demo?: { failLlm?: boolean; slowLlm?: boolean };
  /** Re-selection: exclude these shelter ids (e.g. the one that just filled up). */
  excludeShelterIds?: string[];
  /** Re-selection without a fresh triage. */
  skipTriage?: boolean;
  previousShelterId?: string;
};

export type RunOutput = {
  state: IncidentState;
  shelter?: { id: string; name: string; address: string; lat: number; lng: number; walkMin: number; distanceM: number; elevationM?: number };
  reasons: string[];
  userMessage: string;
  route?: { points: { lat: number; lng: number }[]; distanceM: number; durationS: number; provider: string };
  validatedBy: "llm+rules" | "llm+rules+escalated" | "fallback" | "none";
  costUsd: number;
  llmCalls: number;
};

/// 避難先を決める LLM に与える持ち時間。
///
/// 9 秒だと実データで足りなかった(候補 8 件 + tool calling で上位モデルが
/// 間に合わず、毎回フォールバックに落ちていた)。Vercel の maxDuration が
/// 60 秒あるので、ツール呼び出しと経路取得の分を残して 28 秒まで取る。
/// ここを削ると「AI が決めた」行が AgentLog から消えるので、短くしすぎない。
const LLM_BUDGET_MS = 28000;
const MAX_TOOL_TURNS = 6;

function metaFields(m: OrcaMeta) {
  return {
    requestId: m.requestId,
    model: m.resolvedModel,
    router: m.router,
    fallbackLevel: m.fallbackLevel,
    sessionTier: m.sessionTier,
    promptRef: m.promptRef,
    ...(m.promptRefMissed ? { promptRefMissed: true } : {}),
    latencyMs: m.latencyMs,
    costUsd: m.costUsd,
  };
}

export async function runAgent(input: RunInput): Promise<RunOutput> {
  const { uid, incidentId, alert, location } = input;
  const log = new IncidentLog(incidentId);
  const tiles = new TileCache();
  let llmCalls = 0;
  let state: IncidentState = "assessing";

  log.info("セナヴィが状況を確認しはじめました", `位置情報の取得元: ${labelSource(input.locationSource)}。座標はサーバー内でのみ使い、保存もAIへの送信もしません。`, "both");
  // 震度と警報名はアプリ側に渡す。強い揺れや津波警報のときは、避難先を出す前に
  // 「まず身の安全」を伝える必要があり、その判断材料になる。
  await setIncident(incidentId, {
    uid,
    alertId: alert.id,
    alertType: alert.type,
    alertTitle: alert.title,
    intensity: alert.intensity ?? null,
    intensityLabel: alert.intensityLabel ?? null,
    warnings: alert.warnings ?? [],
    state,
    locationSource: input.locationSource,
    createdAt: new Date().toISOString(),
  });
  await publishStatus(uid, incidentId, state);

  // ---- deterministic context (no LLM) ----
  const [area, hazardHere] = await Promise.all([getAreaCode(location), getHazard(location, tiles)]);
  log.add({ kind: "tool_call", toolName: "get_area", chosenBy: "system", audience: "both", title: "現在地の市区町村を特定しました", detail: area.name, payload: { areaName: area.name } });
  log.add({ kind: "tool_call", toolName: "get_hazard", chosenBy: "system", audience: "both", title: "現在地のハザードを確認しました", detail: `浸水: ${hazardHere.floodLabel} / 津波: ${hazardHere.tsunami ? "想定あり" : "なし"} / 土砂: ${hazardHere.landslide ? "警戒区域" : "なし"}`, payload: hazardHere });

  // ---- 1. triage (cheap tier) ----
  let relevant = true;
  let triageReason = "再選定のため一次判定を省略";
  if (!input.skipTriage) {
    const t = await triage(input, area, hazardHere, log);
    llmCalls += t.calls;
    relevant = t.relevant;
    triageReason = t.reason;
  }
  if (!relevant) {
    state = "not_relevant";
    await finish(state, { reasons: [triageReason], userMessage: "今回は大丈夫。念のため様子を見てるね", validatedBy: "none" });
    return { state, reasons: [triageReason], userMessage: "今回は大丈夫。念のため様子を見てるね", validatedBy: "none", costUsd: log.totalCostUsd, llmCalls };
  }

  // ---- 2. candidates (deterministic, real data) ----
  const disaster = normaliseDisaster(alert.type);
  const sheltersAll = await listShelters(location, disaster, { cache: tiles, limit: 10 });
  const shelters = sheltersAll.filter((s) => !(input.excludeShelterIds ?? []).includes(s.id)).slice(0, 8);
  const crowd = await getCrowd(shelters.map((s) => s.id));
  const candidates = buildCandidates(shelters, crowd);
  log.add({ kind: "tool_call", toolName: "list_shelters", chosenBy: "system", audience: "both", title: `避難場所の候補を${candidates.length}件見つけました`, detail: `国土地理院 指定緊急避難場所(${disasterLabel(disaster)})から半径2.5km・徒歩順`, payload: abstractCandidates(candidates) });

  if (!candidates.length) {
    state = "monitoring_stay";
    const msg = "近くに指定避難場所が見つからないから、今いる建物の上の階で待とう";
    await finish(state, { reasons: ["候補なし"], userMessage: msg, validatedBy: "none" });
    return { state, reasons: ["候補なし"], userMessage: msg, validatedBy: "none", costUsd: log.totalCostUsd, llmCalls };
  }

  // ---- 3. decision (quality tier, tool calling) ----
  let decision: Decision | undefined;
  let chosen: CandidateCtx | undefined;
  let validatedBy: RunOutput["validatedBy"] = "fallback";
  let reasons: string[] = [];

  const attempt = async (escalate: boolean, rejectionNote?: string) => {
    const r = await decide(input, area, hazardHere, disaster, candidates, log, { escalate, rejectionNote });
    llmCalls += r.calls;
    return r.decision;
  };

  try {
    decision = await attempt(false);
    if (decision && decision.shouldEvacuate === false) {
      state = "monitoring_stay";
      const msg = decision.userMessage ?? "今は動かない方が安全。ここで待とう";
      log.add({ kind: "llm_response", audience: "both", title: "セナヴィの判断: 今は避難不要", detail: decision.reasons.join(" / ") });
      await finish(state, { reasons: decision.reasons, userMessage: msg, validatedBy: "llm+rules" });
      return { state, reasons: decision.reasons, userMessage: msg, validatedBy: "llm+rules", costUsd: log.totalCostUsd, llmCalls };
    }
    if (decision) {
      const rej = validateLetter(decision.choice, disaster, candidates);
      if (!rej) {
        chosen = candidates.find((c) => c.letter === decision!.choice)!;
        validatedBy = "llm+rules";
        reasons = decision.reasons;
        log.add({ kind: "validator", audience: "both", title: `安全ルールを通過: 候補 ${chosen.letter}`, detail: "浸水・津波・土砂・満員・距離の全ルールに適合" });
      } else {
        log.add({ kind: "validator", audience: "both", title: `安全ルールで却下: 候補 ${rej.letter}`, detail: `${rej.message}(rule=${rej.rule})。上位モデルへ一度だけ昇格して再選定します`, payload: rej });
        // ---- escalate once (Frontier Escalation) ----
        const d2 = await attempt(true, `前回の選択 ${rej.letter} は「${rej.message}」で却下されました。別の候補を選んでください。`);
        if (d2?.choice) {
          const rej2 = validateLetter(d2.choice, disaster, candidates);
          if (!rej2) {
            chosen = candidates.find((c) => c.letter === d2.choice)!;
            validatedBy = "llm+rules+escalated";
            reasons = d2.reasons;
            decision = d2;
            log.add({ kind: "validator", audience: "both", title: `安全ルールを通過: 候補 ${chosen.letter}(昇格後)` });
          } else {
            log.add({ kind: "validator", audience: "both", title: `再び却下: 候補 ${rej2.letter}`, detail: rej2.message, payload: rej2 });
          }
        }
      }
    }
  } catch (e: any) {
    log.add({ kind: "fallback", audience: "both", title: "AIの応答が得られませんでした", detail: String(e?.message ?? e).slice(0, 200) });
  }

  // ---- 4. fallback (rule-based) ----
  if (!chosen) {
    const fb = ruleBasedSelect(candidates, disaster);
    if (!fb.chosen) {
      state = "monitoring_stay";
      const msg = "安全に行ける避難場所が見つからないから、今いる建物の上の階で待とう";
      await finish(state, { reasons: fb.reasons, userMessage: msg, validatedBy: "fallback" });
      return { state, reasons: fb.reasons, userMessage: msg, validatedBy: "fallback", costUsd: log.totalCostUsd, llmCalls };
    }
    chosen = fb.chosen;
    reasons = fb.reasons;
    validatedBy = "fallback";
    state = "fallback_guiding";
    log.add({ kind: "fallback", audience: "both", title: `安全ルールで決めました: 候補 ${chosen.letter}`, detail: "AIの返事が遅い/不適切だったため、ルールベース(種別適合・距離・混雑・標高)で選定。案内は止めません" });
  } else {
    state = "proposing";
  }

  // ---- 5. route (no LLM) ----
  const s = chosen.shelter;
  const route = await getRoute(location, s);
  log.add({ kind: "tool_call", toolName: "get_route", chosenBy: "system", audience: "both", title: `徒歩ルートを引きました(約${Math.round(route.durationS / 60)}分)`, detail: route.provider === "ors" ? "OpenRouteService 徒歩経路" : "経路APIが使えないため直線距離で概算" });

  // ---- 6. commit crowd, persist, publish ----
  if (input.previousShelterId && input.previousShelterId !== s.id) await adjustCrowd(input.previousShelterId, -1);
  await adjustCrowd(s.id, +1, s.name);

  // 候補一覧の距離は matrix、地図に描く線は directions と別々のAPIから来るので、
  // 数十mずれる。ユーザーには「線の長さ = 徒歩◯分」に見えてほしいので、
  // 実際に引けた経路があればそちらに合わせる。
  if (route.provider === "ors") {
    s.distanceM = route.distanceM;
    s.walkMin = walkMinutes(route.distanceM);
  }

  // プロンプトで禁じてはいるが、仮名が混じった文がそのまま出ると意味不明になる。
  // 最後にここで直す。
  const userMessage =
    decision?.userMessage && validatedBy !== "fallback" ? deanonymise(decision.userMessage) : "今のうちに、ここへ避難しておこう";
  const shelterOut = { id: s.id, name: s.name, address: s.address, lat: s.lat, lng: s.lng, walkMin: s.walkMin, distanceM: s.distanceM, elevationM: s.elevationM };
  await finish(state, { reasons, userMessage, validatedBy, shelter: shelterOut, route, candidates: candidates.map((c) => ({ id: c.shelter.id, name: c.shelter.name, letter: c.letter, walkMin: c.shelter.walkMin, crowdPct: c.crowd.pct })) });

  return { state, shelter: shelterOut, reasons, userMessage, route, validatedBy, costUsd: log.totalCostUsd, llmCalls };

  // ---------------------------------------------------------------- helpers
  async function finish(st: IncidentState, extra: Record<string, unknown>) {
    log.add({ kind: "cost", audience: "judge", title: `今回のAIコスト: $${log.totalCostUsd.toFixed(4)}(LLM ${llmCalls} 回)`, costUsd: 0, detail: "OrcaRouter usage.cost_usd の合計。経路・ハザード・避難所検索はLLM不使用" });
    await Promise.all([
      setIncident(incidentId, { state: st, ...extra, cost: { totalUsd: log.totalCostUsd, llmCalls } }),
      log.flush(),
    ]);
    const sh = extra.shelter as { name?: string; lat?: number; lng?: number } | undefined;
    const shelterName = sh?.name;
    const pub = await publishStatus(uid, incidentId, st, sh);
    if (st === "proposing" || st === "fallback_guiding") {
      await notifyFriends(uid, "ヒナミチ", `${await displayNameOf(uid)}さんは避難を開始しようとしています${shelterName ? `(${shelterName})` : ""}`, { type: "status", state: pub, incidentId });
    }
  }
}

// ------------------------------------------------------------------ LLM steps

async function triage(input: RunInput, area: AreaInfo, hz: Hazard, log: IncidentLog) {
  const { alert } = input;
  const payload = {
    disaster: { type: alert.type, title: alert.title, intensity: alert.intensityLabel, warnings: alert.warnings, severity: alert.severity, affectedAreaIncludesUser: alert.areaCodes.length === 0 || alert.areaCodes.includes(area.jmaClass20), epicenterDistanceKm: alert.epicenter ? Math.round(kmBetween(input.location, alert.epicenter)) : undefined },
    user: { areaName: area.name, hazardHere: { flood: hz.floodLabel, tsunamiZone: hz.tsunami > 0, landslideZone: hz.landslide } },
  };
  assertNoCoordinates(payload);
  log.add({ kind: "llm_request", audience: "judge", title: "AIに渡した情報(一次判定)", detail: "座標・氏名・端末IDは含まれていません", payload });
  const messages: ChatCompletionMessageParam[] = [{ role: "user", content: JSON.stringify(payload) }];
  try {
    const { data, meta } = await orcaChat({
      tier: "triage", sessionId: input.incidentId, promptName: PROMPT_TRIAGE, systemFallback: TRIAGE_SYSTEM,
      promptVariables: { area_name: area.name, disaster_type: alert.type },
      messages, tools: triageTools, toolChoice: { type: "function", function: { name: "submit_triage" } },
      timeoutMs: 12000, demoFail: input.demo?.failLlm, // 一次判定。小型モデルでも実入力では数秒かかる
    });
    const call = data.choices[0]?.message?.tool_calls?.find((c): c is Extract<typeof c, { type: "function" }> => c.type === "function");
    const args = call ? safeJson(call.function.arguments) : undefined;
    const relevant = typeof args?.relevant === "boolean" ? args.relevant : true;
    const reason = String(args?.reason ?? "判定結果を取得できなかったため安全側に倒します");
    log.add({ kind: "llm_response", audience: "both", title: relevant ? "セナヴィの判断: この災害はあなたに関係あります" : "セナヴィの判断: あなたの地域には影響なし", detail: reason, ...metaFields(meta) });
    return { relevant, reason, calls: 1 };
  } catch (e: any) {
    // Deterministic safety-side fallback
    const relevant = payload.disaster.affectedAreaIncludesUser || (payload.disaster.epicenterDistanceKm ?? 999) < 80 || alert.severity >= 0.7;
    log.add({ kind: "fallback", audience: "both", title: "一次判定AIが応答しなかったためルールで判定", detail: `${String(e?.message ?? e).slice(0, 120)} → ${relevant ? "関係あり(安全側)" : "対象外"}` });
    return { relevant, reason: relevant ? "影響エリア/距離から関係ありと判定(ルール)" : "影響エリア外(ルール)", calls: 1 };
  }
}

async function decide(
  input: RunInput, area: AreaInfo, hz: Hazard, disaster: DisasterType, candidates: CandidateCtx[], log: IncidentLog,
  opts: { escalate: boolean; rejectionNote?: string },
): Promise<{ decision?: Decision; calls: number }> {
  const abstract = abstractCandidates(candidates);
  const ctx = {
    disaster: { type: disaster, title: input.alert.title, intensity: input.alert.intensityLabel, warnings: input.alert.warnings },
    user: { areaName: area.name, hazardHere: { flood: hz.floodLabel, tsunamiZone: hz.tsunami > 0, landslideZone: hz.landslide } },
    ...(opts.rejectionNote ? { note: opts.rejectionNote } : {}),
  };
  assertNoCoordinates(ctx);
  assertNoCoordinates(abstract);
  log.add({ kind: "llm_request", audience: "judge", title: opts.escalate ? "AIに渡した情報(再選定・上位モデル)" : "AIに渡した情報(避難先の判断)", detail: "候補は仮名A〜Hと徒歩分・方角・標高・ハザード・混雑率のみ。座標・実名は渡していません", payload: { ...ctx, candidatesPreview: abstract } });

  const messages: ChatCompletionMessageParam[] = [{ role: "user", content: JSON.stringify(ctx) }];
  const deadline = Date.now() + LLM_BUDGET_MS;
  let calls = 0;
  let listed = false;
  let decision: Decision | undefined;

  for (let turn = 0; turn < MAX_TOOL_TURNS && Date.now() < deadline; turn++) {
    const { data, meta } = await orcaChat({
      tier: "decide", sessionId: input.incidentId, promptName: PROMPT_DECIDE, systemFallback: DECIDE_SYSTEM,
      promptVariables: { disaster_type: disaster, area_name: area.name },
      messages, tools: decideTools, toolChoice: turn === 0 ? "required" : "auto",
      escalateOnce: opts.escalate && turn === 0, timeoutMs: Math.max(2000, deadline - Date.now()), demoFail: input.demo?.failLlm,
    });
    calls++;
    const msg = data.choices[0]?.message;
    if (!msg) break;
    messages.push(msg as any);
    const toolCalls = msg.tool_calls ?? [];
    if (!toolCalls.length) {
      // Model answered in prose — nudge once to call submit_decision
      messages.push({ role: "user", content: "submit_decision ツールで最終判断を返してください。" });
      continue;
    }
    for (const tc of toolCalls) {
      if (tc.type !== "function") continue;
      const name = tc.function.name;
      const args = safeJson(tc.function.arguments) ?? {};
      let result: unknown;
      if (name === "get_hazard") {
        result = { flood: hz.floodLabel, tsunamiZone: hz.tsunami > 0, landslideZone: hz.landslide };
        log.add({ kind: "tool_call", toolName: name, chosenBy: "llm", audience: "both", title: "AIが現在地のハザードを確認しました", ...metaFields(meta), costUsd: undefined });
      } else if (name === "list_shelters") {
        listed = true;
        result = { candidates: abstract };
        log.add({ kind: "tool_call", toolName: name, chosenBy: "llm", audience: "both", title: `AIが避難場所の候補(${abstract.length}件)を取得しました`, detail: `災害種別: ${disasterLabel(disaster)}` });
      } else if (name === "get_crowd") {
        const ids: string[] = Array.isArray(args.ids) ? args.ids : [];
        result = Object.fromEntries(abstract.filter((a) => !ids.length || ids.includes(a.id)).map((a) => [a.id, { crowdPct: a.crowdPct, full: a.full }]));
        log.add({ kind: "tool_call", toolName: name, chosenBy: "llm", audience: "both", title: "AIが混雑状況を確認しました" });
      } else if (name === "submit_decision") {
        decision = {
          shouldEvacuate: args.shouldEvacuate !== false,
          choice: typeof args.choice === "string" ? args.choice.trim().toUpperCase().slice(0, 1) : undefined,
          reasons: Array.isArray(args.reasons) ? args.reasons.map(String).slice(0, 3) : [],
          confidence: typeof args.confidence === "number" ? args.confidence : 0.5,
          userMessage: typeof args.userMessage === "string" ? args.userMessage.slice(0, 60) : undefined,
        };
        log.add({ kind: "llm_response", audience: "both", title: decision.shouldEvacuate ? `セナヴィの判断: 候補 ${decision.choice ?? "?"} へ避難` : "セナヴィの判断: 今は避難不要", detail: `${decision.reasons.join(" / ")}(確信度 ${Math.round(decision.confidence * 100)}%)`, ...metaFields(meta) });
        result = { ok: true };
      } else {
        result = { error: `unknown tool ${name}` };
      }
      messages.push({ role: "tool", tool_call_id: tc.id, content: JSON.stringify(result) });
    }
    if (decision) break;
    if (!listed && turn === MAX_TOOL_TURNS - 2) {
      // System completes the mandatory tool for the model (logged as such)
      messages.push({ role: "user", content: JSON.stringify({ candidates: abstract, note: "list_shelters の結果です(システム補完)。submit_decision を呼んでください" }) });
      log.add({ kind: "tool_call", toolName: "list_shelters", chosenBy: "system", audience: "judge", title: "AIが候補取得を呼ばなかったためシステムが補完しました" });
      listed = true;
    }
  }
  if (!decision) log.add({ kind: "fallback", audience: "judge", title: "AIが制限時間内に最終判断を返しませんでした", detail: `${calls} 回の呼び出し` });
  return { decision, calls };
}

// ------------------------------------------------------------------ small utils
function safeJson(s: string): any {
  try { return JSON.parse(s); } catch { return undefined; }
}
function kmBetween(a: LatLng, b: LatLng) {
  const R = 6371, d2r = Math.PI / 180;
  const dLat = (b.lat - a.lat) * d2r, dLng = (b.lng - a.lng) * d2r;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * d2r) * Math.cos(b.lat * d2r) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}
export function normaliseDisaster(t: string): DisasterType {
  return (["earthquake", "heavy_rain", "flood", "tsunami", "landslide", "storm_surge"] as const).includes(t as any) ? (t as DisasterType) : "earthquake";
}
export function disasterLabel(t: DisasterType) {
  return { earthquake: "地震", heavy_rain: "大雨", flood: "洪水", tsunami: "津波", landslide: "土砂災害", storm_surge: "高潮" }[t];
}
function labelSource(s: LocationSource) {
  return { gps: "実GPS", cached: "直近の取得値(10分以内)", override: "デモ用の固定地点" }[s];
}
async function displayNameOf(uid: string): Promise<string> {
  try {
    const { db, COL } = await import("../firebase.js");
    const d = (await db().collection(COL.users).doc(uid).get()).data() as any;
    return d?.displayName ?? "ご家族";
  } catch {
    return "ご家族";
  }
}

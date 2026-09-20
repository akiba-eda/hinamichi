/**
 * Rule-based selection used when the LLM fails, times out, or every LLM choice is rejected.
 * Guidance must never stop. See 設計書 §6.6.
 */
import type { CandidateCtx, DisasterType } from "./types.js";
import { validateChoice } from "./validator.js";

export function scoreCandidate(c: CandidateCtx, disaster: DisasterType): number {
  const hz = c.shelter.hazard;
  const walk = c.shelter.walkMin;
  const elev = c.shelter.elevationM ?? 0;
  let score = 100;
  score -= Math.min(60, walk * 1.5); // distance
  score -= c.crowd.pct * 0.3; // crowd
  if (disaster === "heavy_rain" || disaster === "flood") {
    score -= (hz?.flood ?? 0) * 15;
    score += Math.min(20, elev * 1.5);
    if (hz?.landslide) score -= 30;
  } else if (disaster === "tsunami") {
    score -= (hz?.tsunami ?? 0) * 25;
    score += Math.min(40, elev * 3);
  } else if (disaster === "landslide") {
    if (hz?.landslide) score -= 50;
  } else {
    // earthquake: mild preference for no flood (aftershock rain) and open space
    score -= (hz?.flood ?? 0) * 3;
  }
  return score;
}

export type FallbackResult = { chosen: CandidateCtx | null; reasons: string[] };

export function ruleBasedSelect(all: CandidateCtx[], disaster: DisasterType): FallbackResult {
  const ok = all.filter((c) => !validateChoice(c, disaster, all));
  const pool = ok.length ? ok : all.filter((c) => !c.crowd.full);
  if (!pool.length) return { chosen: null, reasons: ["利用できる避難場所がありません"] };
  pool.sort((a, b) => scoreCandidate(b, disaster) - scoreCandidate(a, disaster));
  const c = pool[0]!;
  return { chosen: c, reasons: reasonsFor(c, disaster) };
}

export function reasonsFor(c: CandidateCtx, disaster: DisasterType): string[] {
  const r: string[] = [];
  const hz = c.shelter.hazard;
  const kind: Record<DisasterType, string> = {
    earthquake: "地震の指定避難場所",
    heavy_rain: "洪水時の指定避難場所",
    flood: "洪水時の指定避難場所",
    tsunami: "津波の指定避難場所",
    landslide: "土砂災害の指定避難場所",
    storm_surge: "高潮の指定避難場所",
  };
  r.push(kind[disaster]);
  if (disaster === "tsunami") r.push(c.shelter.elevationM != null ? `標高${c.shelter.elevationM}m` : "津波浸水想定なし");
  else if (hz && hz.flood === 0) r.push("浸水想定なし");
  else if (hz) r.push(`浸水想定 ${hz.floodLabel}`);
  else r.push(`徒歩${c.shelter.walkMin}分`);
  r.push(`混雑${c.crowd.pct}%`);
  return r.slice(0, 3);
}

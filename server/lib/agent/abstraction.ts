/**
 * Data minimisation: convert real shelters (with coordinates & names) into abstract candidates
 * the LLM can reason about. The mapping letter→shelter stays in server memory only.
 */
import type { Shelter } from "../tools/shelters.js";
import type { Crowd } from "../tools/crowd.js";
import type { AbstractCandidate, CandidateCtx } from "./types.js";
import { FLOOD_LABEL } from "../tools/hazard.js";

export const LETTERS = ["A", "B", "C", "D", "E", "F", "G", "H"] as const;

/** Strip anything that could identify a place (numbers, kanji place-name tails) from free text. */
export function sanitiseNote(s?: string): string | undefined {
  if (!s) return undefined;
  const t = s.replace(/[0-9０-９]+/g, "").replace(/[（(].*?[)）]/g, "").trim();
  return t.length ? t.slice(0, 40) : undefined;
}

export function buildCandidates(shelters: Shelter[], crowd: Record<string, Crowd>): CandidateCtx[] {
  return shelters.slice(0, LETTERS.length).map((s, i) => ({
    letter: LETTERS[i]!,
    shelter: s,
    crowd: crowd[s.id] ?? { assigned: 0, capacity: 300, pct: 0, full: false },
  }));
}

export function abstractCandidates(ctx: CandidateCtx[]): AbstractCandidate[] {
  return ctx.map(({ letter, shelter, crowd }) => ({
    id: letter,
    walkMin: shelter.walkMin,
    direction: shelter.direction,
    elevationM: shelter.elevationM,
    flood: shelter.hazard ? FLOOD_LABEL[shelter.hazard.flood] : "不明",
    tsunami: shelter.hazard ? (shelter.hazard.tsunami ? FLOOD_LABEL[shelter.hazard.tsunami] : "浸水想定なし") : "不明",
    landslide: shelter.hazard?.landslide ?? false,
    crowdPct: crowd.pct,
    full: crowd.full,
    note: sanitiseNote(shelter.remarks),
  }));
}

/** Assert that a payload about to be sent to the LLM carries no coordinates. Defensive. */
export function assertNoCoordinates(payload: unknown): void {
  const s = JSON.stringify(payload);
  // lat/lng-looking decimals like 35.68xx or 139.7xx
  if (/\b(1[2-4][0-9]|[2-4][0-9])\.\d{3,}\b/.test(s)) {
    throw new Error("data-minimisation violation: coordinate-like number in LLM payload");
  }
  if (/"(lat|lng|latitude|longitude)"/i.test(s)) {
    throw new Error("data-minimisation violation: coordinate key in LLM payload");
  }
}

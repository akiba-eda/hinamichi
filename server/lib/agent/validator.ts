/**
 * SafetyValidator — hard rules that the LLM's choice must pass before it reaches a human.
 * Pure function so it is unit-testable. See 設計書 §6.5.
 */
import type { CandidateCtx, DisasterType } from "./types.js";

export type Rejection = { letter: string; rule: string; message: string };

export function validateChoice(
  choice: CandidateCtx,
  disaster: DisasterType,
  all: CandidateCtx[],
): Rejection | null {
  const hz = choice.shelter.hazard;
  const reject = (rule: string, message: string): Rejection => ({ letter: choice.letter, rule, message });

  if (choice.crowd.full) return reject("crowd_full", "満員のため却下");

  if ((disaster === "heavy_rain" || disaster === "flood") && hz && hz.flood >= 2) {
    return reject("flood_depth", `浸水想定 ${hz.floodLabel} のため却下`);
  }
  if (disaster === "tsunami" && hz && hz.tsunami >= 1) {
    return reject("tsunami_zone", "津波浸水想定区域のため却下");
  }
  if (disaster === "tsunami" && choice.shelter.elevationM != null && choice.shelter.elevationM < 5) {
    // Only reject on low elevation when a higher alternative exists
    const higher = all.find((c) => c !== choice && !c.crowd.full && (c.shelter.elevationM ?? 0) >= 5 && !(c.shelter.hazard?.tsunami));
    if (higher) return reject("tsunami_low_elevation", `標高 ${choice.shelter.elevationM}m と低いため却下`);
  }
  if ((disaster === "landslide" || disaster === "heavy_rain") && hz?.landslide) {
    return reject("landslide_zone", "土砂災害警戒区域のため却下");
  }
  if (choice.shelter.walkMin > 40) {
    const nearer = all.find((c) => c !== choice && !c.crowd.full && c.shelter.walkMin <= 40);
    if (nearer) return reject("too_far", `徒歩 ${choice.shelter.walkMin} 分は遠すぎるため却下`);
  }
  return null;
}

/** Validate the LLM's letter; returns the rejection (if any). Unknown letters are rejected. */
export function validateLetter(letter: string | undefined, disaster: DisasterType, all: CandidateCtx[]): Rejection | null {
  const c = all.find((x) => x.letter === letter);
  if (!c) return { letter: letter ?? "?", rule: "unknown_candidate", message: "候補にない仮名のため却下" };
  return validateChoice(c, disaster, all);
}

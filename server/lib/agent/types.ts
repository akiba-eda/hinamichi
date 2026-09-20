import type { Hazard } from "../tools/hazard.js";
import type { DisasterType, Shelter } from "../tools/shelters.js";
import type { Crowd } from "../tools/crowd.js";

export type { DisasterType };

export type AlertDoc = {
  id: string;
  type: DisasterType;
  source: "p2pquake" | "jma" | "demo";
  title: string; // e.g. "地震(震度6弱)" / "大雨警報・洪水警報"
  severity: number; // 0..1
  intensity?: number; // earthquake JMA scale numeric
  intensityLabel?: string;
  warnings?: string[]; // JMA warning names
  areaCodes: string[]; // class20 (7-digit) codes affected; empty = nationwide broadcast
  epicenter?: { lat: number; lng: number; name?: string };
  issuedAt: string; // ISO
  demoTargetUid?: string; // demo alerts are only delivered to this uid
};

export type IncidentState =
  | "assessing"
  | "not_relevant"
  | "monitoring_stay"
  | "proposing" // decision made, waiting for user approval / timeout
  | "guiding"
  | "reselecting"
  | "arrived"
  | "safe_zone"
  | "fallback_guiding"
  | "closed";

export type PublicStatus = "safe" | "assessing" | "evacuating" | "arrived" | "safe_zone" | "unknown";

/** What the LLM sees for one candidate — no coordinates, no real names. */
export type AbstractCandidate = {
  id: string; // "A".."H"
  walkMin: number;
  direction: string;
  elevationM?: number;
  flood: string; // label
  tsunami: string;
  landslide: boolean;
  crowdPct: number;
  full: boolean;
  note?: string; // remarks (sanitised)
};

export type CandidateCtx = {
  letter: string;
  shelter: Shelter;
  crowd: Crowd;
};

export type Decision = {
  shouldEvacuate: boolean;
  choice?: string; // letter
  reasons: string[];
  confidence: number; // 0..1
  userMessage?: string; // one friendly sentence
};

export type AgentLogKind =
  | "tool_call"
  | "tool_result"
  | "llm_request"
  | "llm_response"
  | "validator"
  | "fallback"
  | "action"
  | "approval"
  | "cost"
  | "info";

export type AgentLogEntry = {
  seq: number;
  at: string;
  kind: AgentLogKind;
  title: string; // one-line, user-facing (Japanese)
  detail?: string; // expanded text
  audience: "user" | "judge" | "both";
  toolName?: string;
  chosenBy?: "llm" | "system";
  requestId?: string; // X-Orca-Request-Id → GET /v1/generation で確定コスト
  model?: string;
  router?: string;
  fallbackLevel?: number;
  sessionTier?: string;
  promptRef?: string;
  latencyMs?: number;
  costUsd?: number;
  payload?: unknown; // e.g. the exact abstracted input sent to the LLM
};

export type LocationSource = "gps" | "cached" | "override";

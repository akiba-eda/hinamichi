/**
 * OrcaRouter client — the single place every LLM call goes through.
 * See 設計書 §7 / §18. Records resolved model, fallback level, session tier, prompt ref and cost.
 */
import OpenAI from "openai";
import type { ChatCompletionMessageParam, ChatCompletionTool } from "openai/resources/chat/completions";

export type Tier = "triage" | "decide";

export type OrcaMeta = {
  requestId?: string;
  router?: string;
  resolvedModel?: string;
  fallbackLevel: number;
  fallbackModel?: string;
  sessionTier?: string;
  promptRef?: string;
  /** prompt_ref を要求したのに OrcaRouter 側で解決されなかった。 */
  promptRefMissed?: boolean;
  costUsd?: number;
  promptTokens?: number;
  completionTokens?: number;
  latencyMs: number;
};

export type OrcaCallOpts = {
  tier: Tier;
  /** Session id (= incidentId) for OrcaRouter session affinity / escalation. */
  sessionId: string;
  /** Managed prompt name in OrcaRouter Prompts; falls back to `systemFallback` when disabled. */
  promptName: string;
  promptVariables?: Record<string, unknown>;
  systemFallback: string;
  messages: ChatCompletionMessageParam[];
  tools?: ChatCompletionTool[];
  toolChoice?: "auto" | "required" | { type: "function"; function: { name: string } };
  /** Frontier escalation: run this one call on the strong tier. */
  escalateOnce?: boolean;
  timeoutMs?: number;
  /** Demo: force a failure to exercise the fallback path. */
  demoFail?: boolean;
  temperature?: number;
};

let client: OpenAI | undefined;
function getClient(): OpenAI {
  if (client) return client;
  const apiKey = process.env.ORCA_API_KEY;
  if (!apiKey) throw new Error("ORCA_API_KEY is not set");
  client = new OpenAI({ apiKey, baseURL: process.env.ORCA_BASE_URL ?? "https://api.orcarouter.ai/v1" });
  return client;
}

export function routerFor(tier: Tier): string {
  return tier === "triage"
    ? process.env.ORCA_ROUTER_TRIAGE ?? "orcarouter/hina-triage"
    : process.env.ORCA_ROUTER_DECIDE ?? "orcarouter/hina-decide";
}

export function fallbackChain(tier: Tier): string[] {
  const raw = tier === "triage" ? process.env.ORCA_FALLBACK_TRIAGE : process.env.ORCA_FALLBACK_DECIDE;
  return (raw ?? "").split(",").map((s) => s.trim()).filter(Boolean).slice(0, 5);
}

export const usePromptRef = () => (process.env.ORCA_USE_PROMPT_REF ?? "false") === "true";

/** Mustache-lite substitution used only for the local fallback prompt. */
export function fillTemplate(t: string, vars: Record<string, unknown> = {}): string {
  return t.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, k) => {
    const v = (k as string).split(".").reduce((o: any, p: string) => (o == null ? o : o[p]), vars as any);
    return v == null ? "" : String(v);
  });
}

export async function orcaChat(opts: OrcaCallOpts) {
  if (opts.demoFail) throw new Error("demo: forced LLM failure");
  const c = getClient();
  const t0 = Date.now();

  // システムプロンプトは**常に**自前でも送る。
  //
  // `prompt_ref` は名前が間違っていても 400 にならず、黙って素通りする
  // (実測: 存在しない名前でも 200 が返り、注入されたときだけ X-Orca-Prompt が付く)。
  // 登録側に任せきりにすると、打ち間違いひとつでセナヴィが素の LLM になる。
  // 命に関わる判断をさせているので、指示が消える方の事故は許容できない。
  // 注入が効いた場合は同じ趣旨の指示が二重になるだけで害はない。
  const messages: ChatCompletionMessageParam[] = [
    { role: "system", content: fillTemplate(opts.systemFallback, opts.promptVariables) },
    ...opts.messages,
  ];

  const bodyExtra: Record<string, unknown> = {};
  const chain = fallbackChain(opts.tier);
  if (chain.length) bodyExtra.extra_body = { route: "fallback", models: chain };
  if (usePromptRef()) {
    bodyExtra.prompt_ref = { name: opts.promptName, label: "production", variables: opts.promptVariables ?? {} };
  }

  const headers: Record<string, string> = {
    "X-OrcaRouter-Include-Cost": "true",
    "X-OrcaRouter-Session-Id": opts.sessionId,
  };
  if (opts.escalateOnce) headers["X-OrcaRouter-Escalate"] = "once";

  const { data, response } = await c.chat.completions
    .create(
      {
        model: routerFor(opts.tier),
        messages,
        tools: opts.tools,
        tool_choice: opts.toolChoice,
        temperature: opts.temperature ?? 0.2,
        ...bodyExtra,
      } as any,
      { headers, timeout: opts.timeoutMs ?? 8000, maxRetries: 0 },
    )
    .withResponse();

  const h = (k: string) => response.headers.get(k) ?? undefined;
  const usage: any = data.usage ?? {};
  const meta: OrcaMeta = {
    requestId: h("x-orca-request-id"),
    router: h("x-orca-router"),
    resolvedModel: h("x-orca-resolved-model") ?? data.model,
    fallbackLevel: Number(h("x-orca-fallback-level") ?? 0),
    fallbackModel: h("x-orca-fallback-model"),
    sessionTier: h("x-orca-session-tier"),
    promptRef: h("x-orca-prompt"),
    // prompt_ref を送ったのに注入されなかった = 登録名が違う。黙って進むと
    // 気づけないので、記録に残せるようにしておく。
    promptRefMissed: usePromptRef() && !h("x-orca-prompt"),
    costUsd: typeof usage.cost_usd === "number" ? usage.cost_usd : undefined,
    promptTokens: usage.prompt_tokens,
    completionTokens: usage.completion_tokens,
    latencyMs: Date.now() - t0,
  };
  return { data, meta };
}

/** Settled cost lookup (optional, used when closing an incident). */
export async function settledCost(requestId: string): Promise<number | undefined> {
  const base = process.env.ORCA_BASE_URL ?? "https://api.orcarouter.ai/v1";
  const r = await fetch(`${base}/generation?id=${encodeURIComponent(requestId)}`, {
    headers: { Authorization: `Bearer ${process.env.ORCA_API_KEY}` },
  });
  if (!r.ok) return undefined;
  const j: any = await r.json();
  return typeof j?.data?.total_cost === "number" ? j.data.total_cost : undefined;
}

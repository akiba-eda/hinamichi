/**
 * Verify OrcaRouter wiring with your key: model list, cost header, tool calling.
 *   cd server && ORCA_API_KEY=sk-orca-... npx tsx scripts/orcaCheck.ts
 */
import { orcaChat, routerFor } from "../lib/orca.js";
const base = process.env.ORCA_BASE_URL ?? "https://api.orcarouter.ai/v1";
const r = await fetch(`${base}/models`, { headers: { Authorization: `Bearer ${process.env.ORCA_API_KEY}` } });
const models: any = await r.json();
const ids: string[] = (models.data ?? []).map((m: any) => m.id);
console.log(`models available: ${ids.length}`);
console.log(ids.filter((i) => /mini|flash|haiku|lite/.test(i)).slice(0, 8), "...cheap");
console.log(ids.filter((i) => /gpt-4o$|gpt-5|opus|sonnet|pro$/.test(i)).slice(0, 8), "...strong");
for (const tier of ["triage", "decide"] as const) {
  try {
    const { data, meta } = await orcaChat({
      tier, sessionId: "orca-check", promptName: "hina-triage-system", systemFallback: "You are a test. Call the tool.",
      messages: [{ role: "user", content: "ping" }],
      tools: [{ type: "function", function: { name: "pong", parameters: { type: "object", properties: { ok: { type: "boolean" } }, required: ["ok"] } } }],
      toolChoice: "required",
    });
    console.log(`[${tier}] router=${routerFor(tier)} →`, meta, "tool_calls:", data.choices[0]?.message?.tool_calls?.length ?? 0);
  } catch (e: any) {
    console.log(`[${tier}] FAILED:`, e?.status, e?.message?.slice(0, 200));
  }
}

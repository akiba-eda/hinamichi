/**
 * 直近のインシデントと AgentLog を読み出す。
 *   cd server && npx tsx --env-file=.env scripts/lastIncident.ts
 *
 * アプリの「セナヴィの記録」に出るのと同じ中身をターミナルで見るための道具。
 * Vercel のランタイムログより速くて、判断の根拠(LLM に渡した入力・却下・昇格・
 * コスト)がそのまま残っているので、まずここを見る。
 */
import { db, COL } from "../lib/firebase.js";

const q = await db().collection(COL.incidents).orderBy("createdAt", "desc").limit(1).get();
if (q.empty) {
  console.log("インシデントがまだありません");
  process.exit(0);
}
const doc = q.docs[0]!;
const d = doc.data();
console.log("=== incident", doc.id, "===");
console.log({
  state: d.state,
  alertTitle: d.alertTitle,
  alertType: d.alertType,
  shelter: d.shelter?.name,
  validatedBy: d.validatedBy,
  reasons: d.reasons,
  cost: d.cost,
  routeProvider: d.route?.provider,
  routePoints: d.route?.points?.length,
  createdAt: d.createdAt,
});

const logs = await doc.ref.collection("agentLog").orderBy("at").get();
console.log(`\n=== agentLog (${logs.size}件) ===`);
for (const l of logs.docs) {
  const e = l.data();
  const bits = [
    e.model && `model=${e.model}`,
    e.router && `router=${e.router}`,
    e.fallbackLevel ? `fallback=L${e.fallbackLevel}` : null,
    e.latencyMs && `${e.latencyMs}ms`,
    e.costUsd ? `$${e.costUsd}` : null,
  ].filter(Boolean);
  console.log(`[${e.kind}] ${e.title}${bits.length ? "  (" + bits.join(" ") + ")" : ""}`);
  if (e.detail) console.log(`        ${e.detail}`);
  if (e.payload) console.log(`        payload: ${JSON.stringify(e.payload).slice(0, 400)}`);
}

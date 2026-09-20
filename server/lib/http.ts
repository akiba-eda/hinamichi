import type { VercelRequest, VercelResponse } from "@vercel/node";
import { auth } from "./firebase.js";

export class HttpError extends Error {
  constructor(public status: number, message: string, public code = "error") {
    super(message);
  }
}

export type Handler = (req: VercelRequest, res: VercelResponse, ctx: Ctx) => Promise<unknown>;
export type Ctx = { uid?: string };

/** Wrap a handler: JSON body, CORS, error mapping. */
export function route(opts: { methods: string[]; auth?: "user" | "cron" | "none" }, fn: Handler) {
  return async (req: VercelRequest, res: VercelResponse) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.setHeader("Access-Control-Allow-Methods", opts.methods.join(","));
    if (req.method === "OPTIONS") return res.status(204).end();
    try {
      if (!opts.methods.includes(req.method ?? "")) throw new HttpError(405, "method not allowed");
      const ctx: Ctx = {};
      if (opts.auth === "user") ctx.uid = await requireUser(req);
      if (opts.auth === "cron") requireCron(req);
      const out = await fn(req, res, ctx);
      if (!res.headersSent) res.status(200).json(out ?? { ok: true });
    } catch (e: any) {
      const status = e instanceof HttpError ? e.status : 500;
      const body = { error: e?.code ?? "error", message: e?.message ?? String(e) };
      if (status >= 500) console.error("[api]", req.url, e);
      if (!res.headersSent) res.status(status).json(body);
    }
  };
}

export async function requireUser(req: VercelRequest): Promise<string> {
  const h = req.headers.authorization ?? "";
  const m = /^Bearer (.+)$/.exec(h);
  if (!m) throw new HttpError(401, "missing bearer token", "unauthenticated");
  try {
    const decoded = await auth().verifyIdToken(m[1]!);
    return decoded.uid;
  } catch {
    throw new HttpError(401, "invalid token", "unauthenticated");
  }
}

export function requireCron(req: VercelRequest) {
  const token = (req.query.token as string | undefined) ?? req.headers["x-cron-token"];
  if (!process.env.CRON_TOKEN || token !== process.env.CRON_TOKEN) {
    throw new HttpError(401, "bad cron token", "unauthenticated");
  }
}

export function body<T>(req: VercelRequest): T {
  const b = req.body;
  if (b == null) return {} as T;
  if (typeof b === "string") return JSON.parse(b) as T;
  return b as T;
}

export function requireDemoAdmin(uid: string) {
  const allow = (process.env.DEMO_ADMIN_UIDS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (allow.length && !allow.includes(uid)) throw new HttpError(403, "not a demo admin", "forbidden");
}

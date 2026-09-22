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
      if (!opts.methods.includes(req.method ?? "")) throw new HttpError(405, "この操作は受け付けていません");
      const ctx: Ctx = {};
      if (opts.auth === "user") ctx.uid = await requireUser(req);
      if (opts.auth === "cron") requireCron(req);
      const out = await fn(req, res, ctx);
      if (!res.headersSent) res.status(200).json(out ?? { ok: true });
    } catch (e: any) {
      const isHttp = e instanceof HttpError;
      const isZod = e?.name === "ZodError";
      const status = isHttp ? e.status : isZod ? 400 : 500;
      // 利用者の画面に出るのは message なので、内部の例外文やスタックを載せない。
      // 原因はログに残す。
      const message = isHttp ? e.message : isZod ? "送られた内容に不備があります" : "サーバーで問題が起きました。しばらくしてからもう一度お試しください";
      const body = { error: isHttp ? e.code : isZod ? "bad_request" : "error", message };
      if (status >= 500 || isZod) console.error("[api]", req.url, e);
      if (!res.headersSent) res.status(status).json(body);
    }
  };
}

export async function requireUser(req: VercelRequest): Promise<string> {
  const h = req.headers.authorization ?? "";
  const m = /^Bearer (.+)$/.exec(h);
  if (!m) throw new HttpError(401, "ログインが必要です", "unauthenticated");
  try {
    const decoded = await auth().verifyIdToken(m[1]!);
    return decoded.uid;
  } catch {
    throw new HttpError(401, "ログインの有効期限が切れました。アプリを開き直してください", "unauthenticated");
  }
}

export function requireCron(req: VercelRequest) {
  const token = (req.query.token as string | undefined) ?? req.headers["x-cron-token"];
  if (!process.env.CRON_TOKEN || token !== process.env.CRON_TOKEN) {
    throw new HttpError(401, "監視ジョブの認証に失敗しました", "unauthenticated");
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
  if (allow.length && !allow.includes(uid)) throw new HttpError(403, "デモ操作が許可されていません", "forbidden");
}

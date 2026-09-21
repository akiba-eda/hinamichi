import type { VercelRequest, VercelResponse } from "@vercel/node";

import health from "../lib/routes/health.js";
import agentAction from "../lib/routes/agent/action.js";
import agentPosition from "../lib/routes/agent/position.js";
import agentReselect from "../lib/routes/agent/reselect.js";
import agentRun from "../lib/routes/agent/run.js";
import demoCrowd from "../lib/routes/demo/crowd.js";
import demoFire from "../lib/routes/demo/fire.js";
import demoFriends from "../lib/routes/demo/friends.js";
import demoReset from "../lib/routes/demo/reset.js";
import friendsAccept from "../lib/routes/friends/accept.js";
import friendsMessage from "../lib/routes/friends/message.js";
import friendsShare from "../lib/routes/friends/share.js";
import meRegister from "../lib/routes/me/register.js";
import sheltersNearby from "../lib/routes/shelters/nearby.js";
import watchDisasters from "../lib/routes/watch/disasters.js";
import weatherNowcast from "../lib/routes/weather/nowcast.js";

type Handler = (req: VercelRequest, res: VercelResponse) => unknown | Promise<unknown>;

/**
 * 全エンドポイントを 1 つの Serverless Function に束ねる振り分け。
 *
 * Vercel の Hobby プランは 1 デプロイあたり 12 関数までで、`api/` 直下に
 * ファイルを置く方式だと 15 本になって越える。実装は `lib/routes/` に移し、
 * ここから呼ぶ ── **URL は従来どおり**なので、アプリ側の変更は要らない。
 *
 * 新しいエンドポイントを足すときは `lib/routes/` にファイルを作り、
 * この表に 1 行足す。関数の数は増えない。
 */
const routes: Record<string, Handler> = {
  "health": health,
  "agent/action": agentAction,
  "agent/position": agentPosition,
  "agent/reselect": agentReselect,
  "agent/run": agentRun,
  "demo/crowd": demoCrowd,
  "demo/fire": demoFire,
  "demo/friends": demoFriends,
  "demo/reset": demoReset,
  "friends/accept": friendsAccept,
  "friends/message": friendsMessage,
  "friends/share": friendsShare,
  "me/register": meRegister,
  "shelters/nearby": sheltersNearby,
  "watch/disasters": watchDisasters,
  "weather/nowcast": weatherNowcast,
};

/** `/api/agent/run?x=1` → `agent/run`。
 *
 * `req.query.path` は環境によって空で来ることがある(本番で実際に空だった)ので、
 * URL から取るのを主にして、query は保険に回す。 */
function pathOf(req: VercelRequest): string {
  const fromUrl = (req.url ?? "").split("?")[0]!.replace(/^\/+api\/?/, "");
  if (fromUrl) return fromUrl.replace(/\/+$/, "");
  const raw = req.query.path;
  return (Array.isArray(raw) ? raw.join("/") : (raw ?? "")).replace(/^\/+|\/+$/g, "");
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const path = pathOf(req);
  const fn = routes[path];
  if (!fn) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    return res.status(404).json({ error: "not_found", message: `no route for /api/${path}`, routes: Object.keys(routes) });
  }
  return fn(req, res);
}

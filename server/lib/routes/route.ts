import { z } from "zod";
import { route, body } from "../http.js";
import { getRoute } from "../tools/route.js";

/**
 * 2 点間の徒歩経路。合流地点までの道案内に使う。
 *
 * 避難経路と同じ `getRoute` を通すので、描かれる線も徒歩分も避難時と
 * 同じ出し方になる ── 画面ごとに違う数字が出ると、どちらが正しいのか
 * 分からなくなる。経路 API が落ちたら直線に切り替わる点も同じ。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req) => {
  const b = z
    .object({ fromLat: z.number(), fromLng: z.number(), toLat: z.number(), toLng: z.number() })
    .parse(body(req));
  const r = await getRoute({ lat: b.fromLat, lng: b.fromLng }, { lat: b.toLat, lng: b.toLng });
  return r;
});

import { z } from "zod";
import { route, body } from "../../http.js";
import { getAreaCode, getPlaceName } from "../../tools/areaCode.js";

/**
 * 自分がいまどの市区町村にいるかを返すだけ。**何も保存しない。**
 *
 * 端末はこれで得たコードで FCM のトピックを購読する。そうすれば、その土地に
 * 警報が出たときだけ鳴らせて、なおかつサーバーは誰がどこにいるかを持たない。
 */
export default route({ methods: ["POST"], auth: "user" }, async (req) => {
  const b = z.object({ lat: z.number(), lng: z.number() }).parse(body(req));
  const area = await getAreaCode(b);
  return { class20: area.jmaClass20, prefCd: area.prefCd, name: (await getPlaceName(b)) ?? area.name };
});

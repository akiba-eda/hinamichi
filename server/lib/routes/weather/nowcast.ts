import { z } from "zod";
import { route, body } from "../../http.js";
import { getRainNowcast } from "../../tools/weather.js";

/** 平時のセナヴィの一言。直近60分の雨雲ナウキャスト。何も保存しない。 */
export default route({ methods: ["POST"], auth: "user" }, async (req) => {
  const b = z.object({ lat: z.number(), lng: z.number() }).parse(body(req));
  return getRainNowcast(b);
});

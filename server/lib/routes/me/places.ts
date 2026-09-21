import { z } from "zod";
import { route, body, HttpError } from "../../http.js";
import { db, COL, FieldValue } from "../../firebase.js";

const Place = z.object({
  id: z.string().optional(),
  name: z.string().min(1).max(20),
  lat: z.number(),
  lng: z.number(),
  /** 到着とみなす半径。既定150mは、集合住宅の敷地と測位誤差を吸収する幅。 */
  radiusM: z.number().min(50).max(1000).default(150),
  kind: z.enum(["home", "work", "school", "shelter", "other"]).default("other"),
});

/** よく行く場所の登録・削除。到着/出発の判定に使う。 */
export default route({ methods: ["POST"], auth: "user" }, async (req, _res, ctx) => {
  const b = z.object({ place: Place.optional(), remove: z.string().optional() }).parse(body(req));
  const list = db().collection(COL.places).doc(ctx.uid!).collection("list");

  if (b.remove) {
    await list.doc(b.remove).delete();
    return { ok: true, removed: b.remove };
  }
  if (!b.place) throw new HttpError(400, "place も remove もありません", "bad_request");

  const ref = b.place.id ? list.doc(b.place.id) : list.doc();
  const { id: _ignored, ...fields } = b.place;
  await ref.set({ ...fields, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { ok: true, placeId: ref.id };
});

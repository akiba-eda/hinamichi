import { db, COL } from "./lib/firebase.js";
const uid = "j0XOh0I89fP4SG6OfYHyEQ6hdzx1";
const loc = (await db().collection(COL.locations).doc(uid).get()).data() as any;
console.log("最後に受け取った位置:", loc ? { lat: loc.lat, lng: loc.lng, at: loc.at?.toDate?.()?.toISOString?.(), areaName: loc.areaName } : "(なし)");
const s = await db().collection(COL.places).doc(uid).get();
console.log("inside:", (s.data() as any)?.inside ?? "(なし)");
const ev = await db().collection(COL.placeEvents).doc(uid).collection("list").orderBy("createdAt", "desc").limit(6).get();
for (const d of ev.docs) console.log("  ", d.data().placeName, d.data().arrived ? "着いた" : "出た");

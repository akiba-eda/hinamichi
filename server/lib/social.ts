import { db, COL } from "./firebase.js";
import { HttpError } from "./http.js";

/**
 * 2人のやりとりを入れる場所の名前。
 *
 * uid を並べ替えて繋ぐ ── どちらから送っても同じ名前になるので、
 * スレッドの対応表を別に持たずに済む。Firestore のルール側でも
 * この名前を割って当事者かどうかを判定できる。
 */
export function threadId(a: string, b: string): string {
  return [a, b].sort().join("_");
}

/** 相手が自分を友だちとして登録しているか。していない相手には送らせない。 */
export async function assertFriend(uid: string, friendUid: string) {
  if (uid === friendUid) throw new HttpError(400, "自分には送れません", "bad_request");
  const d = await db().collection(COL.friends).doc(uid).collection("list").doc(friendUid).get();
  if (!d.exists || (d.data() as any)?.status !== "accepted") {
    throw new HttpError(403, "友だちではありません", "forbidden");
  }
}

export async function displayNameOf(uid: string): Promise<string> {
  const d = await db().collection(COL.users).doc(uid).get();
  return ((d.data() as any)?.displayName as string) ?? "友だち";
}

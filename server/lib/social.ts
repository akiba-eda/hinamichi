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

/**
 * 合流から1人が抜けたあとの姿。
 *
 * 「抜ける」と「解散」を分けるための判定。押した人だけが外れ、残りが
 * 1人以下になった時点で合流そのものを閉じる ── 1人だけの合流は、
 * 旗が出たまま誰とも落ち合えない状態になるので残す意味が無い。
 *
 * 呼んだ人がメンバーでない場合は何も変えない(members をそのまま返す)。
 */
export function membersAfterLeave(members: string[], uid: string): { members: string[]; active: boolean } {
  const unique = Array.from(new Set(members));
  if (!unique.includes(uid)) return { members: unique, active: unique.length > 1 };
  const rest = unique.filter((m) => m !== uid);
  return { members: rest, active: rest.length > 1 };
}

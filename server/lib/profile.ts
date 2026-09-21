import { db, COL } from "./firebase.js";

/** 一覧に出すために、相手の `friends/{them}/list/{me}` へ写す分。 */
export type ProfileCard = { displayName: string; avatarImage?: string | null; avatarMood?: string | null };

export function cardOf(user: any): ProfileCard {
  return {
    displayName: user?.displayName ?? "友だち",
    avatarImage: user?.avatarImage ?? null,
    avatarMood: user?.avatarMood ?? null,
  };
}

/**
 * 自分のプロフィールを、自分を登録しているフレンドの一覧へ配る。
 *
 * 一覧は `friends/{uid}/list` を 1 回読むだけで描けるようにしたい
 * (相手ごとに `users/{friendUid}` を引くと N+1 になるし、ルール上も読めない)。
 * そのため表示名とアイコンは**写して持たせる**。更新時にここで配り直す。
 */
export async function fanOutProfile(uid: string, card: ProfileCard) {
  const mine = await db().collection(COL.friends).doc(uid).collection("list").get();
  if (mine.empty) return;
  const batch = db().batch();
  for (const d of mine.docs) {
    batch.set(db().collection(COL.friends).doc(d.id).collection("list").doc(uid), card, { merge: true });
  }
  await batch.commit();
}

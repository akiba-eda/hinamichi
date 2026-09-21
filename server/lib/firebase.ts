import { cert, getApps, initializeApp, type App } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

let app: App | undefined;

function init(): App {
  if (app) return app;
  if (getApps().length) return (app = getApps()[0]!);
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
  if (!b64) throw new Error("FIREBASE_SERVICE_ACCOUNT_B64 is not set");
  const sa = JSON.parse(Buffer.from(b64, "base64").toString("utf8"));
  app = initializeApp({ credential: cert(sa), projectId: sa.project_id });
  return app;
}

export const db = () => getFirestore(init());
export const auth = () => getAuth(init());
export const fcm = () => getMessaging(init());
export { FieldValue, Timestamp };

/** Firestore collection names (single source of truth) */
export const COL = {
  users: "users",
  friends: "friends", // friends/{uid}/list/{friendUid}
  alerts: "alerts",
  alertsSeen: "alertsSeen",
  incidents: "incidents", // incidents/{id}/agentLog/{seq}
  statuses: "statuses",
  locations: "locations", // locations/{uid} — 最後に受け取った位置。許可した相手だけが読める
  shelterCrowd: "shelterCrowd",
  shelterCache: "shelterCache",
  approvals: "approvals",
  messages: "messages", // messages/{threadId}/list/{messageId}
  places: "places", // places/{uid}/list/{placeId} — よく行く場所
  placeEvents: "placeEvents", // placeEvents/{uid}/list/{eventId} — 到着・出発
  meetups: "meetups",
} as const;

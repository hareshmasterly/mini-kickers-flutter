import * as admin from "firebase-admin";

// Initialise the Admin SDK once. All other modules import `db` from
// here so we don't accidentally double-init in test or watch mode.
if (admin.apps.length === 0) {
  admin.initializeApp();
}

export const db = admin.firestore();
export const FieldValue = admin.firestore.FieldValue;
export const Timestamp = admin.firestore.Timestamp;

// Collection name constants — keep these in sync with the client's
// `MatchService` constants. Drift here would silently break sync
// (server writing to one collection, client reading another).
export const COL_USERS = "users";
export const COL_HANDLES = "handles";
export const COL_MATCHES = "matches";
export const COL_QUEUE = "matchmaking_queue";
export const COL_ROOMS = "rooms";
export const COL_CONNECTIONS = "connections";

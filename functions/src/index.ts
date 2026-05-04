// Entry point for Mini Kickers Cloud Functions.
//
// Each handler is exported by name from its module so `firebase
// deploy --only functions:<name>` works for selective deploys
// (useful for hot-fixing one function without redeploying the rest).
//
// Deploy order recommendation:
//   1. `firebase deploy --only firestore:rules`
//   2. `firebase deploy --only functions`
//
// First-time setup:
//   • Enable Anonymous Auth in Firebase Console
//   • Configure TTL policies in the Firestore Console:
//       - `users` collection,           field `ttl`
//       - `handles` collection,         field `ttl`
//       - `matchmaking_queue` collection, field `ttl`
//       - `rooms` collection,           field `ttl`
//       - `matches` collection,         field `ttl`
//       - `connections` collection,     field `ttl`
//   • `cd functions && npm install && npm run build`
//   • `firebase deploy --only functions`

export { onQueueWrite } from "./matchmaking";
export { onUserAuthDeleted, scheduledCleanup } from "./cleanup";

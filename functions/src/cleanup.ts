import * as functionsV1 from "firebase-functions/v1";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";

import {
  COL_CONNECTIONS,
  COL_HANDLES,
  COL_MATCHES,
  COL_QUEUE,
  COL_ROOMS,
  COL_USERS,
  FieldValue,
  Timestamp,
  db,
} from "./admin";

// Fires when Firebase Auth deletes an anonymous user (which it does
// after 30 days of inactivity per the project's auth policy). We
// clean up everything tied to that uid so dead accounts don't leave
// dangling docs forever.
//
// What gets cleaned up:
//   1. `users/{uid}`               — the profile
//   2. `handles/{handle_lower}`    — the handle reservation
//   3. `matchmaking_queue/{uid}`   — any active queue entry
//   4. `connections/{uid}`         — any active heartbeat
//   5. `matches/...`               — any in-flight match marked
//                                    forfeited (the opponent wins)
//
// All deletes are idempotent — we use `.delete()` which is a no-op
// for missing docs, and the match cleanup uses `.update()` only
// when the doc actually contains the user.
//
// Note: this is a **v1 trigger** because v2 doesn't yet expose an
// equivalent for `auth.user().onDelete`. Mixing v1 + v2 in one
// codebase is supported.
export const onUserAuthDeleted = functionsV1.auth
  .user()
  .onDelete(async (user) => {
    const uid = user.uid;
    logger.info("Cleaning up after auth delete", { uid });

    // 1. Read profile first so we know which handle to free.
    const userRef = db.collection(COL_USERS).doc(uid);
    const userSnap = await userRef.get();
    const handleLower = userSnap.exists ?
      (userSnap.data()?.handle_lower as string | undefined) :
      undefined;

    // 2. Best-effort deletes. Each one is wrapped so a single failure
    // doesn't block the rest — orphan cleanup is more important than
    // perfect atomicity.
    const ops: Promise<unknown>[] = [
      userRef.delete().catch((e) => logger.warn("user delete failed", { e })),
      db
        .collection(COL_QUEUE)
        .doc(uid)
        .delete()
        .catch((e) => logger.warn("queue delete failed", { e })),
      db
        .collection(COL_CONNECTIONS)
        .doc(uid)
        .delete()
        .catch((e) => logger.warn("connection delete failed", { e })),
    ];
    if (handleLower) {
      ops.push(
        db
          .collection(COL_HANDLES)
          .doc(handleLower)
          .delete()
          .catch((e) => logger.warn("handle delete failed", { e })),
      );
    }
    await Promise.all(ops);

    // 3. Forfeit any active matches that have this player. We query
    // both `red.uid` and `blue.uid` because the user could be on
    // either side. Use `Promise.all` so both queries run in parallel.
    await _forfeitActiveMatchesFor(uid);
    logger.info("Cleanup done", { uid });
  });

async function _forfeitActiveMatchesFor(uid: string): Promise<void> {
  const ttlAfterForfeit = Timestamp.fromDate(
    new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
  );
  const queryPaths: ["red.uid" | "blue.uid", string][] = [
    ["red.uid", uid],
    ["blue.uid", uid],
  ];
  await Promise.all(
    queryPaths.map(async ([field, value]) => {
      const snap = await db
        .collection(COL_MATCHES)
        .where("status", "==", "in_progress")
        .where(field, "==", value)
        .limit(20)
        .get();
      const writes = snap.docs.map((d) =>
        d.ref
          .update({
            status: "forfeited",
            forfeited_by_uid: uid,
            completed_at: FieldValue.serverTimestamp(),
            ttl: ttlAfterForfeit,
          })
          .catch((e) =>
            logger.warn("match forfeit update failed", { matchId: d.id, e }),
          ),
      );
      await Promise.all(writes);
    }),
  );
}

// Daily safety-net sweep. The Firestore TTL policies (configured in
// the console on the `ttl` field of each collection) handle the
// vast majority of cleanup automatically, but TTL deletion can lag
// up to 24h. This scheduled function reaps anything past its
// expiry IMMEDIATELY so we don't pay for stale storage on busy
// days.
//
// Cron: every day at 03:00 UTC — low-traffic window. Set to
// `every 24 hours` to keep it cheap (one invocation per day).
export const scheduledCleanup = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Etc/UTC",
    region: "us-central1",
  },
  async () => {
    const now = Timestamp.now();
    let totalDeleted = 0;
    for (const col of [COL_QUEUE, COL_ROOMS, COL_CONNECTIONS, COL_MATCHES]) {
      // Filter on `ttl <= now`. Each iteration deletes up to 200 docs
      // — large enough to keep up with even a busy day in one pass,
      // small enough to fit comfortably under Firestore's 500-write
      // batch limit.
      const expired = await db
        .collection(col)
        .where("ttl", "<=", now)
        .limit(200)
        .get();
      if (expired.empty) continue;
      const batch = db.batch();
      expired.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      totalDeleted += expired.size;
      logger.info("Reaped expired docs", { col, count: expired.size });
    }
    logger.info("Scheduled cleanup done", { totalDeleted });
  },
);

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";

import {
  COL_MATCHES,
  COL_QUEUE,
  FieldValue,
  Timestamp,
  db,
} from "./admin";

// Server-side matchmaking pair-up.
//
// Triggered every time a new doc lands in `matchmaking_queue/{uid}`.
// We pick the OLDEST other waiting player (by `created_at`), and
// inside a transaction:
//   1. Re-read both queue docs and bail if either is gone (someone
//      else paired one of them up while we were checking).
//   2. Delete both queue docs atomically.
//   3. Create a fresh `matches/{matchId}` doc with both players.
//
// Coin-toss randomness: we use Math.random() to decide who plays
// red. Server-side randomness gives both clients the SAME assignment
// (vs the old client-side approach where two clients could pair up
// each other and each compute a different outcome).
//
// Why a Firestore trigger instead of a scheduled function?
// - Lower latency: pair-up happens within ~1s of the second player
//   joining the queue, vs up to a minute with cron-style scheduling.
// - Cheaper: only fires when there's actually a new queue write,
//   instead of polling every minute even when the queue is empty.
// - Race-safe: the transaction inside `_runPairUp` handles
//   simultaneous trigger fires (both clients added to queue at the
//   same moment → both functions try to pair → only one wins).
//
// The client still has a fallback `tryClientSidePairUp` for when
// this function isn't deployed yet — see `MatchService` in the
// Flutter app.
export const onQueueWrite = onDocumentCreated(
  {
    document: `${COL_QUEUE}/{uid}`,
    region: "us-central1",
    // Concurrency is fine — even if two trigger invocations race for
    // the same opponent, the transaction's optimistic locking picks
    // exactly one winner and the loser silently no-ops.
    concurrency: 40,
  },
  async (event) => {
    const newUid = event.params.uid;
    const newPlayer = event.data?.data();
    if (!newPlayer) {
      logger.warn("Queue trigger fired without snapshot", { newUid });
      return;
    }

    try {
      // Find the oldest OTHER waiting player. Limit 5 so a long
      // queue doesn't blow our read budget — we only need ONE
      // candidate, the buffer is for the rare case where the head
      // of the queue races us and we have to retry.
      const candidates = await db
        .collection(COL_QUEUE)
        .orderBy("created_at")
        .limit(5)
        .get();

      const opponentDoc = candidates.docs.find((d) => d.id !== newUid);
      if (!opponentDoc) {
        logger.info("No opponent yet — leaving queued", { newUid });
        return;
      }

      const matchId = await _runPairUp(
        newUid,
        opponentDoc.id,
        newPlayer,
        opponentDoc.data(),
      );
      if (matchId) {
        logger.info("Paired up", { newUid, opponent: opponentDoc.id, matchId });
      }
    } catch (e) {
      logger.error("Pair-up failed", { newUid, error: String(e) });
    }
  },
);

// Atomic pair-up. Returns the new match id on success, null when
// the optimistic transaction loses to another client/function.
async function _runPairUp(
  uidA: string,
  uidB: string,
  playerA: FirebaseFirestore.DocumentData,
  playerB: FirebaseFirestore.DocumentData,
): Promise<string | null> {
  const queueRefA = db.collection(COL_QUEUE).doc(uidA);
  const queueRefB = db.collection(COL_QUEUE).doc(uidB);
  const matchRef = db.collection(COL_MATCHES).doc();

  try {
    await db.runTransaction(async (tx) => {
      // Re-read both queue docs inside the transaction so Firestore
      // can detect concurrent deletes and abort us if either is gone.
      const [snapA, snapB] = await Promise.all([
        tx.get(queueRefA),
        tx.get(queueRefB),
      ]);
      if (!snapA.exists || !snapB.exists) {
        throw new Error("RACE_LOST");
      }
      tx.delete(queueRefA);
      tx.delete(queueRefB);
      tx.set(matchRef, _buildInitialMatch(playerA, playerB));
    });
    return matchRef.id;
  } catch (e) {
    if (e instanceof Error && e.message === "RACE_LOST") return null;
    throw e;
  }
}

// Builds the initial match doc in the SAME shape the client uses
// (see `OnlineMatch.toMap` and `MatchService._initialMatchMap` in
// the Flutter app). Drift here = clients fail to parse the doc.
function _buildInitialMatch(
  playerA: FirebaseFirestore.DocumentData,
  playerB: FirebaseFirestore.DocumentData,
): FirebaseFirestore.DocumentData {
  // Server-side coin toss — also decides who kicks off. Whichever
  // player is assigned `red` will be the kickoff team (the bloc
  // initialises with `turn: red`).
  const aIsRed = Math.random() < 0.5;
  const red = aIsRed ? playerA : playerB;
  const blue = aIsRed ? playerB : playerA;

  // Initial board layout — must match `GameConfig.initialTokens()`
  // and `GameConfig.initialBall` exactly.
  const initialTokens = [
    { id: "r0", team: "red", c: 1, r: 2 },
    { id: "r1", team: "red", c: 1, r: 3 },
    { id: "r2", team: "red", c: 2, r: 4 },
    { id: "b0", team: "blue", c: 9, r: 2 },
    { id: "b1", team: "blue", c: 9, r: 3 },
    { id: "b2", team: "blue", c: 8, r: 4 },
  ];

  // 24h TTL on in-flight matches (configurable via Firestore TTL
  // policy on the `ttl` field). Completed matches push it out to
  // 7 days from `markMatchCompleted` on the client side.
  const ttl = Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000));

  return {
    status: "in_progress",
    red: _playerSubMap(red),
    blue: _playerSubMap(blue),
    phase: "coinToss",
    turn: "red", // red always kicks off — assignment was the toss
    tokens: initialTokens,
    ball: { c: 5, r: 3 },
    dice: null,
    red_dice: null,
    blue_dice: null,
    selected_token_id: null,
    highlights: [],
    red_score: 0,
    blue_score: 0,
    time_left: 900, // default match length, mirrors GameConfig.matchSeconds
    match_seconds: 900,
    is_rolling: false,
    show_goal_flash: false,
    message: "Toss the coin to decide who kicks off!",
    created_at: FieldValue.serverTimestamp(),
    last_move_at: FieldValue.serverTimestamp(),
    ttl,
  };
}

// Strips queue-only fields off a player doc and returns the canonical
// player sub-map shape used inside match docs.
function _playerSubMap(
  raw: FirebaseFirestore.DocumentData,
): Record<string, unknown> {
  return {
    uid: raw.uid ?? "",
    handle: raw.handle ?? "",
    display_name: raw.display_name ?? raw.displayName ?? "",
    avatar_id: raw.avatar_id ?? raw.avatarId ?? "tiger",
  };
}

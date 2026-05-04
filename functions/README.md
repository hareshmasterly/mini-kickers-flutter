# Mini Kickers — Cloud Functions

TypeScript Cloud Functions backing the online 1v1 feature.

## What's here

- `src/matchmaking.ts` — `onQueueWrite` Firestore trigger. Whenever a
  player joins `matchmaking_queue`, looks for another waiting player
  and atomically pairs them up by creating a `matches/{id}` doc and
  deleting both queue entries.
- `src/cleanup.ts`
  - `onUserAuthDeleted` (v1 Auth trigger) — when Firebase Auth
    deletes an inactive anonymous user, removes the matching profile,
    handle reservation, queue entry, heartbeat, and forfeits any
    in-flight match.
  - `scheduledCleanup` (daily cron) — safety net that reaps any
    Firestore docs whose `ttl` field is past, in case the platform's
    TTL service lags.

The Flutter client has a fallback `tryClientSidePairUp` that runs
every ~3 seconds while a player is in the queue, so the lobby still
works without these functions deployed — but pair-up latency drops
from "up to 60s" to "<1s" once `onQueueWrite` is live.

## First-time setup

```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

Make sure you're logged into the right Firebase project:

```bash
firebase use mini-kickers-7b71c
```

## Iterating locally

```bash
npm run build:watch          # in one terminal
firebase emulators:start --only functions,firestore   # in another
```

## TTL policies (one-time, in Firebase Console)

Firestore → TTL → Add policy on these collections, all using the
`ttl` field:

- `users`
- `handles`
- `matchmaking_queue`
- `rooms`
- `matches`
- `connections`

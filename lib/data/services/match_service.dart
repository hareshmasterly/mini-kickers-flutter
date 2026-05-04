import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/models/match_player.dart';
import 'package:mini_kickers/data/models/online_match.dart';
import 'package:mini_kickers/data/models/room_code.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/data/services/user_service.dart';

/// Centralised online-match orchestration.
///
/// Five responsibilities:
///   1. **Random matchmaking** — enqueue, listen for pair-up, unqueue
///      on cancel
///   2. **Room codes** — create / join 4-letter friend-pair codes
///   3. **Match lifecycle** — create the match doc, listen for state
///      changes, push moves, mark complete/forfeit
///   4. **Heartbeats** — periodic write to `connections/{uid}` so the
///      opponent can detect drop-outs
///   5. **Cleanup** — leaves queues / deletes heartbeat on dispose
///
/// All Firestore writes use the **current uid** from
/// [UserService.instance.uid]. The service throws `StateError` if
/// called before [UserService.init] has run.
///
/// Designed to be a singleton consumed by:
///   • Matchmaking lobby UI
///   • Room-code create / join UI
///   • OnlineGameController (the bridge between this service and the
///     local GameBloc)
class MatchService {
  MatchService._();

  static final MatchService instance = MatchService._();

  static const String _matchesCollection = 'matches';
  static const String _queueCollection = 'matchmaking_queue';
  static const String _roomsCollection = 'rooms';
  static const String _connectionsCollection = 'connections';

  /// 4-letter room codes pulled from this alphabet. Skips visually
  /// confusable characters (no 0/O, 1/I/L, B/8) so codes can be
  /// shared verbally without ambiguity.
  static const String _roomCodeAlphabet = 'ACDEFGHJKMNPQRTUVWXYZ23456789';

  /// Heartbeat interval. The opponent's connection is considered
  /// stale if no heartbeat arrives for 3× this interval.
  static const Duration _heartbeatInterval = Duration(seconds: 10);

  static final Random _rng = Random.secure();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String get _uid {
    final String? uid = UserService.instance.uid;
    if (uid == null) {
      throw StateError(
        'MatchService called before UserService.init completed',
      );
    }
    return uid;
  }

  MatchPlayer get _selfAsPlayer {
    final dynamic profile = UserService.instance.profile;
    if (profile == null) {
      throw StateError(
        'MatchService requires a confirmed user profile',
      );
    }
    return MatchPlayer(
      uid: _uid,
      handle: profile.handle as String,
      displayName: profile.displayName as String,
      avatarId: profile.avatarId as String,
    );
  }

  Timer? _heartbeatTimer;
  String? _activeHeartbeatMatchId;

  // ── Random matchmaking ─────────────────────────────────────────

  /// Add the current user to the matchmaking queue. Returns a
  /// snapshot stream the caller listens on to detect pair-up — when
  /// our queue doc is deleted (by the pair-up function or another
  /// client's transaction), the stream will emit a `not exists`
  /// snapshot and the caller polls for the resulting match.
  ///
  /// **NOTE:** the actual pair-up logic lives in two places:
  ///   1. **Cloud Function (preferred)** — server picks the oldest
  ///      two queued players, atomically deletes both queue docs,
  ///      creates a `matches/{id}` doc with both players. Most
  ///      reliable, runs even when both apps are backgrounded.
  ///   2. **Client transaction (fallback)** — when no Cloud Function
  ///      is deployed, [tryClientSidePairUp] runs every few seconds
  ///      while the user is in the queue and attempts to pick another
  ///      waiting player.
  Future<Stream<DocumentSnapshot<Map<String, dynamic>>>>
      enterMatchmakingQueue() async {
    final MatchPlayer self = _selfAsPlayer;
    final DocumentReference<Map<String, dynamic>> queueDoc =
        _db.collection(_queueCollection).doc(_uid);
    await queueDoc.set(<String, dynamic>{
      'uid': _uid,
      'handle': self.handle,
      'display_name': self.displayName,
      'avatar_id': self.avatarId,
      'created_at': FieldValue.serverTimestamp(),
      // 5-minute TTL — abandoned queue docs disappear automatically
      // (TTL policy: collection `matchmaking_queue`, field `ttl`).
      'ttl': Timestamp.fromDate(
        DateTime.now().add(const Duration(minutes: 5)),
      ),
    });
    return queueDoc.snapshots();
  }

  /// Best-effort fallback when no Cloud Function is deployed: pick
  /// another player from the queue and atomically pair up. Returns
  /// the new match id on success, null if the queue had no other
  /// player or another client beat us to the pair-up.
  ///
  /// Safe to call repeatedly. The caller (matchmaking lobby) should
  /// poll this every ~3 seconds while waiting.
  Future<String?> tryClientSidePairUp() async {
    try {
      // 1. Find the oldest queued player that ISN'T us.
      final QuerySnapshot<Map<String, dynamic>> waiting = await _db
          .collection(_queueCollection)
          .orderBy('created_at')
          .limit(5) // small batch to avoid scanning a long queue
          .get();
      final Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> others =
          waiting.docs.where((final QueryDocumentSnapshot<
                      Map<String, dynamic>> doc) =>
              doc.id != _uid);
      if (others.isEmpty) return null;
      final QueryDocumentSnapshot<Map<String, dynamic>> opponent =
          others.first;

      // 2. Run a transaction: delete BOTH queue docs + create match.
      //    If anyone else beat us to either queue doc, the transaction
      //    fails and we return null (caller will retry).
      final String matchId = _db.collection(_matchesCollection).doc().id;
      await _db.runTransaction<void>((final Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> selfQueue = await tx
            .get(_db.collection(_queueCollection).doc(_uid));
        final DocumentSnapshot<Map<String, dynamic>> oppQueue = await tx
            .get(_db.collection(_queueCollection).doc(opponent.id));
        if (!selfQueue.exists || !oppQueue.exists) {
          throw _PairUpRaceLost();
        }
        tx.delete(_db.collection(_queueCollection).doc(_uid));
        tx.delete(_db.collection(_queueCollection).doc(opponent.id));
        // Coin-toss for who plays Red. Whoever gets red goes first
        // by default (matches single-player coin-toss conventions).
        final bool selfIsRed = _rng.nextBool();
        final MatchPlayer self = _selfAsPlayer;
        final MatchPlayer opponentPlayer = MatchPlayer.fromMap(
          opponent.data().cast<String, dynamic>(),
        );
        tx.set(
          _db.collection(_matchesCollection).doc(matchId),
          _initialMatchMap(
            red: selfIsRed ? self : opponentPlayer,
            blue: selfIsRed ? opponentPlayer : self,
          ),
        );
      });
      return matchId;
    } on _PairUpRaceLost {
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('MatchService: pair-up failed → $e');
      return null;
    }
  }

  /// Remove ourselves from the matchmaking queue. Idempotent.
  Future<void> leaveMatchmakingQueue() async {
    try {
      await _db.collection(_queueCollection).doc(_uid).delete();
    } catch (_) {/* swallow — non-fatal */}
  }

  // ── Room codes ─────────────────────────────────────────────────

  /// Host a new room. Returns the freshly-generated 4-char code.
  /// Internally retries on collision (extremely rare with 28^4 = 614k
  /// combinations and ttl-cleared dead rooms).
  Future<String> createRoom() async {
    final MatchPlayer self = _selfAsPlayer;
    for (int attempt = 0; attempt < 10; attempt++) {
      final String code = _generateRoomCode();
      final DocumentReference<Map<String, dynamic>> ref =
          _db.collection(_roomsCollection).doc(code);
      try {
        await _db.runTransaction<void>((final Transaction tx) async {
          final DocumentSnapshot<Map<String, dynamic>> existing =
              await tx.get(ref);
          if (existing.exists) {
            throw _CodeCollision();
          }
          tx.set(ref, <String, dynamic>{
            'created_by': self.toMap(),
            'status': RoomStatus.open.wireValue,
            'created_at': FieldValue.serverTimestamp(),
            // 24h TTL for unused codes (Firestore policy: collection
            // `rooms`, field `ttl`).
            'ttl': Timestamp.fromDate(
              DateTime.now().add(const Duration(hours: 24)),
            ),
          });
        });
        return code;
      } on _CodeCollision {
        continue;
      }
    }
    throw StateError('Could not generate a unique room code after 10 tries');
  }

  /// Listen to a room doc — host watches this to know when the second
  /// player has joined (the `match_id` field appears).
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchRoom(
      final String code) {
    return _db
        .collection(_roomsCollection)
        .doc(code.toUpperCase())
        .snapshots();
  }

  /// Joiner side: validate the code, create the match doc, and stamp
  /// the room doc with the new match id. Returns the match id on
  /// success, throws [RoomJoinError] on failure.
  Future<String> joinRoom(final String rawCode) async {
    final String code = rawCode.trim().toUpperCase();
    if (code.length != 4) {
      throw const RoomJoinError(reason: 'Code must be 4 letters');
    }
    final MatchPlayer self = _selfAsPlayer;
    final DocumentReference<Map<String, dynamic>> roomRef =
        _db.collection(_roomsCollection).doc(code);
    final String matchId = _db.collection(_matchesCollection).doc().id;
    try {
      await _db.runTransaction<void>((final Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> roomSnap =
            await tx.get(roomRef);
        if (!roomSnap.exists) {
          throw const RoomJoinError(reason: "We couldn't find that code");
        }
        final RoomCode room = RoomCode.fromMap(
          code,
          roomSnap.data()!,
        );
        if (room.status != RoomStatus.open) {
          throw const RoomJoinError(
            reason: "That room's already taken",
          );
        }
        if (room.createdBy.uid == _uid) {
          throw const RoomJoinError(
            reason: "You can't join your own room",
          );
        }
        // Coin-toss for who plays Red.
        final bool joinerIsRed = _rng.nextBool();
        tx.set(
          _db.collection(_matchesCollection).doc(matchId),
          _initialMatchMap(
            red: joinerIsRed ? self : room.createdBy,
            blue: joinerIsRed ? room.createdBy : self,
          ),
        );
        tx.update(roomRef, <String, dynamic>{
          'status': RoomStatus.matched.wireValue,
          'match_id': matchId,
        });
      });
      return matchId;
    } on RoomJoinError {
      rethrow;
    } catch (e) {
      throw RoomJoinError(reason: 'Something went wrong ($e)');
    }
  }

  // ── Match lifecycle ────────────────────────────────────────────

  /// Listen on a match doc — the OnlineGameController feeds this
  /// stream into the local GameBloc.
  Stream<OnlineMatch> watchMatch(final String matchId) {
    return _db
        .collection(_matchesCollection)
        .doc(matchId)
        .snapshots()
        .where((final DocumentSnapshot<Map<String, dynamic>> snap) =>
            snap.exists)
        .map((final DocumentSnapshot<Map<String, dynamic>> snap) =>
            OnlineMatch.fromMap(snap.id, snap.data()!));
  }

  /// One-shot fetch of a match (used after the room flow when the
  /// host's listener fires with a match_id field).
  Future<OnlineMatch?> getMatch(final String matchId) async {
    final DocumentSnapshot<Map<String, dynamic>> snap = await _db
        .collection(_matchesCollection)
        .doc(matchId)
        .get();
    if (!snap.exists) return null;
    return OnlineMatch.fromMap(snap.id, snap.data()!);
  }

  /// Push a partial state update. Caller (OnlineGameController)
  /// builds the patch from the local bloc's emitted state. We always
  /// stamp `last_move_by_uid` + `last_move_at` so the OPPONENT's
  /// listener can detect "this update came from the other player".
  Future<void> pushStatePatch(
    final String matchId,
    final Map<String, dynamic> patch,
  ) async {
    final Map<String, dynamic> stamped = <String, dynamic>{
      ...patch,
      'last_move_by_uid': _uid,
      'last_move_at': FieldValue.serverTimestamp(),
    };
    await _db
        .collection(_matchesCollection)
        .doc(matchId)
        .update(stamped);
  }

  /// Mark a match completed. Sets `completed_at` and bumps the TTL
  /// so it auto-deletes in 7 days (configure: collection `matches`,
  /// field `ttl`).
  Future<void> markMatchCompleted(final String matchId) async {
    await _db.collection(_matchesCollection).doc(matchId).update(
      <String, dynamic>{
        'status': MatchStatus.completed.wireValue,
        'completed_at': FieldValue.serverTimestamp(),
        'ttl': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
      },
    );
  }

  /// Mark a match forfeited because [forfeitedByUid] disconnected
  /// past the heartbeat timeout. Other player wins by default.
  Future<void> markMatchForfeited(
    final String matchId, {
    required final String forfeitedByUid,
  }) async {
    await _db.collection(_matchesCollection).doc(matchId).update(
      <String, dynamic>{
        'status': MatchStatus.forfeited.wireValue,
        'forfeited_by_uid': forfeitedByUid,
        'completed_at': FieldValue.serverTimestamp(),
        'ttl': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
      },
    );
  }

  // ── Heartbeats ─────────────────────────────────────────────────

  /// Start writing a heartbeat doc every [_heartbeatInterval] for the
  /// duration of the given match. Idempotent — calling again with the
  /// same matchId is a no-op; calling with a different matchId stops
  /// the old one and starts the new one.
  void startHeartbeats(final String matchId) {
    if (_activeHeartbeatMatchId == matchId) return;
    stopHeartbeats();
    _activeHeartbeatMatchId = matchId;
    _writeHeartbeat(matchId);
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (final _) => _writeHeartbeat(matchId),
    );
  }

  void stopHeartbeats() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_activeHeartbeatMatchId != null) {
      _db
          .collection(_connectionsCollection)
          .doc(_uid)
          .delete()
          .ignore();
    }
    _activeHeartbeatMatchId = null;
  }

  Future<void> _writeHeartbeat(final String matchId) async {
    try {
      await _db
          .collection(_connectionsCollection)
          .doc(_uid)
          .set(<String, dynamic>{
        'uid': _uid,
        'match_id': matchId,
        'last_heartbeat': FieldValue.serverTimestamp(),
        // 5-min TTL — heartbeat docs are ephemeral.
        'ttl': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 5)),
        ),
      });
    } catch (_) {/* swallow — next tick will retry */}
  }

  /// One-shot read of the OPPONENT's heartbeat. The OnlineGameController
  /// polls this every few seconds; if the heartbeat is older than 3×
  /// the interval, the local UI shows "opponent disconnected" + offers
  /// a forfeit option.
  Future<DateTime?> readOpponentHeartbeat(final String opponentUid) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _db
          .collection(_connectionsCollection)
          .doc(opponentUid)
          .get();
      if (!snap.exists) return null;
      final Timestamp? hb = snap.data()?['last_heartbeat'] as Timestamp?;
      return hb?.toDate();
    } catch (_) {
      return null;
    }
  }

  // ── Internal helpers ───────────────────────────────────────────

  String _generateRoomCode() {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < 4; i++) {
      sb.write(_roomCodeAlphabet[
          _rng.nextInt(_roomCodeAlphabet.length)]);
    }
    return sb.toString();
  }

  /// Builds the initial Firestore map for a brand-new match. Mirrors
  /// the bloc's `GameState.initial()` shape but stamped with the two
  /// players + match-duration setting.
  Map<String, dynamic> _initialMatchMap({
    required final MatchPlayer red,
    required final MatchPlayer blue,
  }) {
    final int seconds = SettingsService.instance.matchSeconds;
    final List<Token> initialTokens = GameConfig.initialTokens();
    return <String, dynamic>{
      'status': MatchStatus.inProgress.wireValue,
      'red': red.toMap(),
      'blue': blue.toMap(),
      'phase': GamePhase.coinToss.name,
      'turn': Team.red.name,
      'tokens': initialTokens
          .map((final Token t) => <String, dynamic>{
                'id': t.id,
                'team': t.team.name,
                'c': t.c,
                'r': t.r,
              })
          .toList(),
      'ball': <String, dynamic>{
        'c': GameConfig.initialBall.c,
        'r': GameConfig.initialBall.r,
      },
      'dice': null,
      'red_dice': null,
      'blue_dice': null,
      'selected_token_id': null,
      'highlights': const <Map<String, dynamic>>[],
      'red_score': 0,
      'blue_score': 0,
      'time_left': seconds,
      'match_seconds': seconds,
      'is_rolling': false,
      'show_goal_flash': false,
      'message': 'Toss the coin to decide who kicks off!',
      'created_at': FieldValue.serverTimestamp(),
      'last_move_at': FieldValue.serverTimestamp(),
      // Auto-cleanup of in-flight matches after 24h of inactivity.
      // Completed matches push this further out (see
      // [markMatchCompleted]).
      'ttl': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
    };
  }
}

/// Thrown by [MatchService.tryClientSidePairUp] when the optimistic
/// transaction loses to another client. Caught internally; never
/// surfaced.
class _PairUpRaceLost implements Exception {}

/// Thrown by [MatchService.createRoom] when the random code already
/// exists. Caught internally — the loop tries again with a new code.
class _CodeCollision implements Exception {}

/// User-facing error from [MatchService.joinRoom]. Carries a kid-
/// readable [reason] that the lobby UI surfaces directly.
class RoomJoinError implements Exception {
  const RoomJoinError({required this.reason});
  final String reason;

  @override
  String toString() => reason;
}

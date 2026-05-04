import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/models/match_player.dart';
import 'package:mini_kickers/data/models/online_context.dart';
import 'package:mini_kickers/data/models/online_match.dart';
import 'package:mini_kickers/data/services/match_service.dart';
import 'package:mini_kickers/data/services/user_service.dart';

/// Outcome notifications surfaced by [OnlineGameController]. The game
/// screen subscribes to [OnlineGameController.events] to drive its
/// "opponent disconnected" / "opponent forfeited" / "match completed"
/// banners and post-match navigation.
enum OnlineMatchEvent {
  /// Opponent's heartbeat hasn't been seen for longer than
  /// [OnlineGameController.heartbeatTimeout]. The UI surfaces a
  /// non-blocking "opponent disconnected — they have N seconds to
  /// reconnect" banner. If the heartbeat resumes, [opponentReconnected]
  /// fires and the banner clears.
  opponentDisconnected,

  /// Heartbeat resumed after a brief drop. Clears the disconnect banner.
  opponentReconnected,

  /// Status flipped to `forfeited`. The game screen pops back to the
  /// home screen with a "you win by default" toast.
  opponentForfeited,

  /// Status flipped to `completed` (clock ran out / one side won by
  /// goals). Drives the game-over overlay.
  matchCompleted,

  /// Hard sync error — the match doc disappeared, network is dead, or
  /// the bloc rejected the inbound state. The UI surfaces a "lost
  /// connection, please return home" overlay.
  syncError,
}

/// Bridge between [MatchService] (Firestore) and [GameBloc] (local
/// state). Owns FOUR responsibilities for the lifetime of one
/// online match:
///
///   1. **Inbound sync** — listens on `matches/{matchId}` and dispatches
///      [ApplyRemoteStateEvent] for every snapshot whose
///      `last_move_by_uid` is NOT us (filters out echoes of our own
///      writes).
///   2. **Outbound sync** — installs a push hook on the bloc that
///      writes every locally-initiated state change to Firestore.
///   3. **Heartbeats** — keeps `connections/{uid}` alive every 10s and
///      polls the OPPONENT's heartbeat. If we miss 3 ticks we flag
///      [OnlineMatchEvent.opponentDisconnected]; if 6 ticks pass with
///      no heartbeat we [MatchService.markMatchForfeited] and surface
///      [OnlineMatchEvent.opponentForfeited].
///   4. **End-of-match marking** — when the bloc emits
///      `phase: gameOver`, the controller calls
///      [MatchService.markMatchCompleted] so the doc's TTL flips to
///      "delete in 7 days" and the status field reflects reality.
///
/// Lifecycle:
///   • [start]  — subscribe + install hook. Returns a Future that
///                resolves when the first remote sync lands (so the
///                game screen can wait on it before painting).
///   • [dispose] — cancel everything, clear the hook, stop heartbeats.
///                Idempotent; safe to call from `Widget.dispose`.
class OnlineGameController {
  OnlineGameController({
    required this.bloc,
    required this.matchId,
    final MatchService? matchService,
    this.heartbeatTimeout = const Duration(seconds: 30),
    this.forfeitTimeout = const Duration(seconds: 60),
    this.opponentPollInterval = const Duration(seconds: 5),
  }) : _matchService = matchService ?? MatchService.instance;

  final GameBloc bloc;
  final String matchId;
  final MatchService _matchService;

  /// After this long without an opponent heartbeat we surface the
  /// "opponent disconnected" banner. Default 30s — three missed
  /// heartbeats at the [MatchService] 10s interval.
  final Duration heartbeatTimeout;

  /// After this long with no heartbeat we forfeit the match in
  /// favour of the local player and emit [OnlineMatchEvent.opponentForfeited].
  /// Default 60s gives the opponent a full minute to reconnect on a
  /// dodgy network before we declare them out.
  final Duration forfeitTimeout;

  /// How often we poll the opponent's heartbeat doc. 5s is fast
  /// enough for a snappy disconnect indicator without hammering
  /// Firestore reads.
  final Duration opponentPollInterval;

  StreamSubscription<OnlineMatch>? _matchSub;
  Timer? _heartbeatPollTimer;
  bool _disposed = false;
  bool _started = false;
  bool _opponentDisconnectedShown = false;
  bool _terminalStatusSeen = false;
  bool _statsBumped = false;
  Completer<void>? _firstSync;

  final StreamController<OnlineMatchEvent> _events =
      StreamController<OnlineMatchEvent>.broadcast();

  /// Outcome events the game screen subscribes to (disconnect banners,
  /// forfeit notifications, match-completion). The stream is broadcast
  /// so multiple listeners (overlay + analytics) can consume it.
  Stream<OnlineMatchEvent> get events => _events.stream;

  String? get _localUid => UserService.instance.uid;

  /// Subscribe to the match doc, install the push hook, start
  /// heartbeats. Returns once the first inbound sync lands so the
  /// game screen can paint a populated state on entry.
  ///
  /// The first sync also tells us which side we're on (red vs blue),
  /// which is wrapped into the [OnlineContext] attached to every
  /// subsequent local state.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _firstSync = Completer<void>();

    // Heartbeat: writes our own connection doc, polls opponent's.
    _matchService.startHeartbeats(matchId);
    _heartbeatPollTimer = Timer.periodic(
      opponentPollInterval,
      (final _) => _pollOpponentHeartbeat(),
    );

    // Inbound sync: every match doc snapshot becomes either an
    // ApplyRemoteState event (other player moved) or a no-op
    // (echo of our own write).
    _matchSub = _matchService.watchMatch(matchId).listen(
      _onMatchSnapshot,
      onError: (final Object e, final StackTrace st) {
        if (kDebugMode) {
          debugPrint('OnlineGameController: stream error → $e\n$st');
        }
        if (!_disposed && !_events.isClosed) {
          _events.add(OnlineMatchEvent.syncError);
        }
      },
    );

    // Outbound sync: install the bloc's push hook. Do this AFTER
    // subscribing so the first inbound sync (which arrives before
    // any local action could fire) doesn't accidentally race with
    // an empty hook.
    bloc.pushHook = _onBlocStateChange;

    // Wait for the first inbound state so the caller's UI doesn't
    // paint with the bloc's initial (local) state. 10s budget — if
    // Firestore is unreachable that long, the syncError event has
    // already fired.
    try {
      await _firstSync!.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      if (!_disposed && !_events.isClosed) {
        _events.add(OnlineMatchEvent.syncError);
      }
    }
  }

  void _onMatchSnapshot(final OnlineMatch match) {
    if (_disposed) return;
    final String? uid = _localUid;
    if (uid == null) return;

    // Detect terminal-status flips (forfeited / completed) regardless
    // of who triggered them. The losing side's controller still emits
    // these events so the local UI can transition out of gameplay.
    if (!_terminalStatusSeen) {
      if (match.status == MatchStatus.forfeited) {
        _terminalStatusSeen = true;
        // Forfeit stats: the player whose uid is in `forfeited_by_uid`
        // takes the loss; the other player is credited a win.
        _bumpStatsForForfeit(match);
        if (!_events.isClosed) {
          _events.add(OnlineMatchEvent.opponentForfeited);
        }
      } else if (match.status == MatchStatus.completed) {
        _terminalStatusSeen = true;
        // Completed-by-clock stats: bump for the local player based
        // on the final score. Both clients independently call bump
        // — UserService's local cache update is idempotent on
        // matchesPlayed (we guard with [_statsBumped]).
        _bumpStatsForCompletion(match);
        if (!_events.isClosed) {
          _events.add(OnlineMatchEvent.matchCompleted);
        }
      }
    }

    // Skip echoes of our own writes. The active player's state push
    // arrives back via this same stream; without this filter the
    // bloc would re-emit (idempotent, but wasteful + risks subtle
    // reorderings of in-flight UI animations).
    if (match.lastMoveByUid != null && match.lastMoveByUid == uid) {
      // Even when skipping the dispatch, a first-sync completer
      // waiting on a populated state still needs to fire — otherwise
      // start() would time out for the player whose write created
      // the doc. Resolve it here using the inbound match.
      _completeFirstSync();
      return;
    }

    final OnlineContext context = _buildContext(match);

    // First-ever sync also installs the OnlineContext on the bloc.
    // We dispatch a separate AttachOnlineContextEvent (not just bake
    // the context into ApplyRemoteState) so the context survives
    // future ApplyRemoteState events that don't change identity but
    // otherwise replace state wholesale.
    if (bloc.state.online == null) {
      bloc.add(AttachOnlineContextEvent(context: context));
    }

    bloc.add(ApplyRemoteStateEvent(match: match, context: context));
    _completeFirstSync();
  }

  void _completeFirstSync() {
    if (_firstSync != null && !_firstSync!.isCompleted) {
      _firstSync!.complete();
    }
  }

  /// Builds the local OnlineContext from a match snapshot. Stable for
  /// the match's lifetime — only the `opponent` field could change
  /// if we ever added handle-edits mid-match (we don't, so this is
  /// effectively a constant per match).
  OnlineContext _buildContext(final OnlineMatch match) {
    final String uid = _localUid!;
    final Team localTeam = match.teamForUid(uid);
    final MatchPlayer opponent = match.opponentOf(uid);
    return OnlineContext(
      matchId: matchId,
      localUid: uid,
      localTeam: localTeam,
      opponent: opponent,
    );
  }

  /// Push hook: bloc invokes us on every locally-initiated state
  /// transition. We translate the [GameState] into a Firestore
  /// patch and write it via [MatchService.pushStatePatch].
  ///
  /// We DON'T diff against the previous state — Firestore handles
  /// last-write-wins natively, and a full-state push is cheaper
  /// than the diffing logic in dart land for our small (~200 byte)
  /// state shape.
  void _onBlocStateChange(final GameState newState) {
    if (_disposed) return;
    // Defensive: skip pushes before we have an installed online
    // context. Shouldn't happen (the controller installs it before
    // installing the push hook) but cheap to verify.
    if (newState.online == null) return;
    final Map<String, dynamic> patch = _stateToPatch(newState);
    unawaited(
      _matchService.pushStatePatch(matchId, patch).catchError(
        (final Object e, final StackTrace st) {
          if (kDebugMode) {
            debugPrint('OnlineGameController: push failed → $e');
          }
        },
      ),
    );

    // End-of-match marking — flip the doc's status so TTL extends
    // and both clients see the terminal phase. Only the active
    // player's bloc reaches gameOver via the timer or a goal that
    // ends the match (Pass 6 will add an explicit "victory by goals"
    // path); pushing from there is sufficient.
    if (newState.phase == GamePhase.gameOver && !_terminalStatusSeen) {
      _terminalStatusSeen = true;
      unawaited(
        _matchService.markMatchCompleted(matchId).catchError(
          (final Object e, final StackTrace st) {
            if (kDebugMode) {
              debugPrint('OnlineGameController: complete failed → $e');
            }
          },
        ),
      );
    }
  }

  /// Converts a [GameState] into the partial Firestore patch we push.
  /// Uses the same field names as [OnlineMatch.toMap] so the round-
  /// trip through Firestore is bit-for-bit consistent.
  Map<String, dynamic> _stateToPatch(final GameState state) {
    return <String, dynamic>{
      'phase': state.phase.name,
      'turn': state.turn.name,
      'tokens': state.tokens
          .map((final Token t) => <String, dynamic>{
                'id': t.id,
                'team': t.team.name,
                'c': t.c,
                'r': t.r,
              })
          .toList(),
      'ball': <String, dynamic>{'c': state.ball.c, 'r': state.ball.r},
      'dice': state.dice,
      'red_dice': state.redDice,
      'blue_dice': state.blueDice,
      'selected_token_id': state.selectedTokenId,
      'highlights': state.highlights
          .map((final Pos p) => <String, dynamic>{'c': p.c, 'r': p.r})
          .toList(),
      'red_score': state.redScore,
      'blue_score': state.blueScore,
      'time_left': state.timeLeft,
      'is_rolling': state.isRolling,
      'show_goal_flash': state.showGoalFlash,
      'message': state.message,
    };
  }

  /// Bump the local player's stats for a clock-completion finish.
  /// Reads the score from the match doc (NOT the bloc, because the
  /// match doc is the source of truth and may have lagged the local
  /// emit slightly).
  void _bumpStatsForCompletion(final OnlineMatch match) {
    if (_statsBumped) return;
    _statsBumped = true;
    final String? uid = _localUid;
    if (uid == null) return;
    final Team localTeam = match.teamForUid(uid);
    final int ourGoals =
        localTeam == Team.red ? match.redScore : match.blueScore;
    final int theirGoals =
        localTeam == Team.red ? match.blueScore : match.redScore;
    final bool drawn = ourGoals == theirGoals;
    final bool won = ourGoals > theirGoals;
    unawaited(
      UserService.instance.bumpStats(
        won: won,
        drawn: drawn,
        goalsScored: ourGoals,
        goalsConceded: theirGoals,
      ),
    );
  }

  /// Bump for a forfeit. The leaver takes the loss; the other player
  /// is credited a win. Goals scored stay at whatever the doc shows
  /// at forfeit time (often 0–0 if the leaver bailed before the
  /// first goal).
  void _bumpStatsForForfeit(final OnlineMatch match) {
    if (_statsBumped) return;
    _statsBumped = true;
    final String? uid = _localUid;
    if (uid == null) return;
    final bool weForfeited = match.forfeitedByUid == uid;
    final Team localTeam = match.teamForUid(uid);
    final int ourGoals =
        localTeam == Team.red ? match.redScore : match.blueScore;
    final int theirGoals =
        localTeam == Team.red ? match.blueScore : match.redScore;
    unawaited(
      UserService.instance.bumpStats(
        won: !weForfeited,
        drawn: false,
        goalsScored: ourGoals,
        goalsConceded: theirGoals,
      ),
    );
  }

  Future<void> _pollOpponentHeartbeat() async {
    if (_disposed || _terminalStatusSeen) return;
    final OnlineContext? online = bloc.state.online;
    if (online == null) return;
    final String opponentUid = online.opponent.uid;
    final DateTime? lastBeat =
        await _matchService.readOpponentHeartbeat(opponentUid);
    if (_disposed) return;
    final Duration sinceBeat = lastBeat == null
        ? const Duration(days: 1)
        : DateTime.now().difference(lastBeat);

    // Disconnect window — show banner.
    if (sinceBeat >= heartbeatTimeout && !_opponentDisconnectedShown) {
      _opponentDisconnectedShown = true;
      if (!_events.isClosed) {
        _events.add(OnlineMatchEvent.opponentDisconnected);
      }
    } else if (sinceBeat < heartbeatTimeout && _opponentDisconnectedShown) {
      // Heartbeat resumed within the grace window.
      _opponentDisconnectedShown = false;
      if (!_events.isClosed) {
        _events.add(OnlineMatchEvent.opponentReconnected);
      }
    }

    // Forfeit window — they're gone for good. Mark the doc so both
    // sides see the terminal status (the leaver's controller will
    // pick it up if/when they reconnect later).
    if (sinceBeat >= forfeitTimeout && !_terminalStatusSeen) {
      _terminalStatusSeen = true;
      try {
        await _matchService.markMatchForfeited(
          matchId,
          forfeitedByUid: opponentUid,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Forfeit mark failed → $e');
      }
      if (!_events.isClosed) {
        _events.add(OnlineMatchEvent.opponentForfeited);
      }
    }
  }

  /// Tear down EVERYTHING. Safe to call multiple times — second + later
  /// invocations are no-ops. Always called from the game screen's
  /// `dispose`, but also defensively from `start` if subscription
  /// fails so we don't leak the heartbeat timer.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    bloc.pushHook = null;
    _heartbeatPollTimer?.cancel();
    _heartbeatPollTimer = null;
    _matchService.stopHeartbeats();
    await _matchSub?.cancel();
    _matchSub = null;
    if (!_events.isClosed) await _events.close();
    // Clear the bloc's online context so a subsequent local match
    // (or a rematch) starts clean. The bloc filters
    // AttachOnlineContextEvent out of the push hook, so this is safe
    // to do AFTER nulling the hook.
    bloc.add(const AttachOnlineContextEvent(context: null));
  }
}

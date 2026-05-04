import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/models/match_player.dart';

/// Per-match online identity attached to [GameState] when the user is
/// playing an Internet 1v1 (i.e. [GameMode.vsOnline]). For local
/// modes ([GameMode.vsHuman], [GameMode.vsAi]) this field is null.
///
/// The bloc reads it for two things:
///   1. **Action gating** — only allow rolls / token-selects / moves
///      when it's the local player's turn.
///   2. **State sync** — every state mutation triggered by a local
///      event is mirrored to Firestore by the [OnlineGameController]
///      via a push hook.
///
/// Created by [OnlineGameController.start] from a freshly-fetched
/// [OnlineMatch] doc and replaced (NOT mutated in place) on each
/// [ApplyRemoteStateEvent] so freezed equality keeps treating the
/// surrounding [GameState] as a brand-new instance.
class OnlineContext {
  const OnlineContext({
    required this.matchId,
    required this.localUid,
    required this.localTeam,
    required this.opponent,
  });

  /// Doc id of the `matches/{matchId}` doc both clients are watching.
  final String matchId;

  /// uid of the player on THIS device. Used by action gates and by
  /// the controller's "did the OTHER player just move?" filter
  /// (skip pushing state echoes from our own writes).
  final String localUid;

  /// Which team this device is controlling — derived from the match
  /// doc by comparing [localUid] to `red.uid` / `blue.uid`. Stable
  /// for the lifetime of the match (no team-swap mid-game).
  final Team localTeam;

  /// Snapshot of the OPPONENT's identity at match-create time. We
  /// keep a copy here (not a reference into the live match doc) so
  /// the in-game opponent display stays stable even if the underlying
  /// `users/{uid}` doc is deleted via TTL while a long match is in
  /// progress.
  final MatchPlayer opponent;

  /// Convenience: true when it's the local player's turn to act.
  /// All RollDice / SelectToken / MoveTo handlers in [GameBloc]
  /// short-circuit when this is false in online mode.
  bool isLocalTurn(final Team currentTurn) => currentTurn == localTeam;

  OnlineContext copyWith({
    final MatchPlayer? opponent,
  }) =>
      OnlineContext(
        matchId: matchId,
        localUid: localUid,
        localTeam: localTeam,
        opponent: opponent ?? this.opponent,
      );

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      (other is OnlineContext &&
          other.matchId == matchId &&
          other.localUid == localUid &&
          other.localTeam == localTeam &&
          other.opponent.uid == opponent.uid);

  @override
  int get hashCode =>
      Object.hash(matchId, localUid, localTeam, opponent.uid);
}

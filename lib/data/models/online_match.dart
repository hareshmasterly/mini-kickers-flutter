import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/models/match_player.dart';

/// Lifecycle status of an online match.
///
///   • `waiting`    — match doc created, waiting for both players to
///                    confirm presence (used briefly during room-code
///                    flow). Most random-matchmade matches skip this
///                    and go straight to `inProgress`.
///   • `inProgress` — coin toss decided, gameplay active.
///   • `completed`  — match ended naturally (time ran out / someone
///                    won). Both clients show game-over screen.
///   • `forfeited`  — one player disconnected past the timeout. Other
///                    player wins by default.
///   • `cancelled`  — pre-game cancellation (player left lobby before
///                    coin toss). No stats bumped.
enum MatchStatus { waiting, inProgress, completed, forfeited, cancelled }

extension MatchStatusX on MatchStatus {
  String get wireValue {
    switch (this) {
      case MatchStatus.waiting:
        return 'waiting';
      case MatchStatus.inProgress:
        return 'in_progress';
      case MatchStatus.completed:
        return 'completed';
      case MatchStatus.forfeited:
        return 'forfeited';
      case MatchStatus.cancelled:
        return 'cancelled';
    }
  }

  static MatchStatus fromWire(final String? raw) {
    switch (raw) {
      case 'waiting':
        return MatchStatus.waiting;
      case 'in_progress':
        return MatchStatus.inProgress;
      case 'completed':
        return MatchStatus.completed;
      case 'forfeited':
        return MatchStatus.forfeited;
      case 'cancelled':
        return MatchStatus.cancelled;
      default:
        return MatchStatus.waiting;
    }
  }
}

/// Single source of truth for an online match. Stored in
/// `matches/{matchId}` and watched by both clients via a snapshot
/// listener. Every move on either side mutates this doc; both sides
/// see the change within ~200 ms.
///
/// Schema is deliberately FLAT (no nested objects beyond the two
/// player blocks and the small token/highlight arrays). Flat docs
/// are cheaper to read, simpler to mutate atomically, and play nicer
/// with Firestore security rules.
class OnlineMatch {
  const OnlineMatch({
    required this.id,
    required this.status,
    required this.red,
    required this.blue,
    required this.phase,
    required this.turn,
    required this.tokens,
    required this.ball,
    required this.redScore,
    required this.blueScore,
    required this.timeLeft,
    required this.matchSeconds,
    required this.isRolling,
    required this.showGoalFlash,
    required this.message,
    this.dice,
    this.redDice,
    this.blueDice,
    this.selectedTokenId,
    this.highlights = const <Pos>[],
    this.lastMoveByUid,
    this.createdAt,
    this.lastMoveAt,
    this.completedAt,
    this.forfeitedByUid,
  });

  final String id;
  final MatchStatus status;

  // ── Players ────────────────────────────────────────────────────
  final MatchPlayer red;
  final MatchPlayer blue;

  // ── Game state (mirror of GameState fields) ────────────────────
  final GamePhase phase;
  final Team turn;
  final List<Token> tokens;
  final Pos ball;
  final int? dice;
  final int? redDice;
  final int? blueDice;
  final String? selectedTokenId;
  final List<Pos> highlights;
  final int redScore;
  final int blueScore;
  final int timeLeft;
  final int matchSeconds;
  final bool isRolling;
  final bool showGoalFlash;
  final String message;

  // ── Meta ───────────────────────────────────────────────────────
  /// uid of the player who wrote the last move event. Used to detect
  /// "did the OTHER player just move" → drives the local bloc updates.
  final String? lastMoveByUid;
  final Timestamp? createdAt;
  final Timestamp? lastMoveAt;
  final Timestamp? completedAt;
  /// Set when status == forfeited — uid of the player who disconnected.
  final String? forfeitedByUid;

  /// Convenience: returns the player object for a given team.
  MatchPlayer playerFor(final Team team) =>
      team == Team.red ? red : blue;

  /// Convenience: returns the team a given uid is playing as. Throws
  /// `StateError` if the uid isn't part of this match (caller bug).
  Team teamForUid(final String uid) {
    if (uid == red.uid) return Team.red;
    if (uid == blue.uid) return Team.blue;
    throw StateError('uid $uid is not in match $id');
  }

  /// Returns the OPPOSING player object given a uid. Useful for
  /// "who am I playing against?" displays.
  MatchPlayer opponentOf(final String uid) =>
      uid == red.uid ? blue : red;

  // ── Serialization ──────────────────────────────────────────────

  Map<String, dynamic> toMap() => <String, dynamic>{
        'status': status.wireValue,
        'red': red.toMap(),
        'blue': blue.toMap(),
        'phase': phase.name,
        'turn': turn.name,
        'tokens': tokens.map(_tokenToMap).toList(),
        'ball': _posToMap(ball),
        'dice': dice,
        'red_dice': redDice,
        'blue_dice': blueDice,
        'selected_token_id': selectedTokenId,
        'highlights': highlights.map(_posToMap).toList(),
        'red_score': redScore,
        'blue_score': blueScore,
        'time_left': timeLeft,
        'match_seconds': matchSeconds,
        'is_rolling': isRolling,
        'show_goal_flash': showGoalFlash,
        'message': message,
        if (lastMoveByUid != null) 'last_move_by_uid': lastMoveByUid,
        if (forfeitedByUid != null) 'forfeited_by_uid': forfeitedByUid,
      };

  factory OnlineMatch.fromMap(
    final String id,
    final Map<String, dynamic> data,
  ) {
    final List<dynamic> rawTokens =
        (data['tokens'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> rawHighlights =
        (data['highlights'] as List<dynamic>?) ?? const <dynamic>[];
    final Map<String, dynamic>? rawBall =
        (data['ball'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();

    return OnlineMatch(
      id: id,
      status: MatchStatusX.fromWire(data['status'] as String?),
      red: MatchPlayer.fromMap(
        ((data['red'] as Map<dynamic, dynamic>?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      ),
      blue: MatchPlayer.fromMap(
        ((data['blue'] as Map<dynamic, dynamic>?) ??
                const <String, dynamic>{})
            .cast<String, dynamic>(),
      ),
      phase: _parsePhase(data['phase'] as String?),
      turn: _parseTeam(data['turn'] as String?),
      tokens: rawTokens
          .whereType<Map<dynamic, dynamic>>()
          .map((final Map<dynamic, dynamic> raw) =>
              raw.cast<String, dynamic>())
          .map(_tokenFromMap)
          .toList(),
      ball: rawBall != null ? _posFromMap(rawBall) : const Pos(5, 3),
      dice: (data['dice'] as num?)?.toInt(),
      redDice: (data['red_dice'] as num?)?.toInt(),
      blueDice: (data['blue_dice'] as num?)?.toInt(),
      selectedTokenId: data['selected_token_id'] as String?,
      highlights: rawHighlights
          .whereType<Map<dynamic, dynamic>>()
          .map((final Map<dynamic, dynamic> raw) =>
              raw.cast<String, dynamic>())
          .map(_posFromMap)
          .toList(),
      redScore: (data['red_score'] as num?)?.toInt() ?? 0,
      blueScore: (data['blue_score'] as num?)?.toInt() ?? 0,
      timeLeft: (data['time_left'] as num?)?.toInt() ?? 0,
      matchSeconds: (data['match_seconds'] as num?)?.toInt() ?? 900,
      isRolling: (data['is_rolling'] as bool?) ?? false,
      showGoalFlash: (data['show_goal_flash'] as bool?) ?? false,
      message: (data['message'] as String?) ?? '',
      lastMoveByUid: data['last_move_by_uid'] as String?,
      createdAt: data['created_at'] as Timestamp?,
      lastMoveAt: data['last_move_at'] as Timestamp?,
      completedAt: data['completed_at'] as Timestamp?,
      forfeitedByUid: data['forfeited_by_uid'] as String?,
    );
  }

  // ── Token / Pos helpers ────────────────────────────────────────
  // Token + Pos live in game_models.dart and don't have their own
  // (de)serializers — keeping them here so the online-match layer
  // owns its own wire format and game_models stays Firestore-agnostic.

  static Map<String, dynamic> _tokenToMap(final Token t) =>
      <String, dynamic>{
        'id': t.id,
        'team': t.team.name,
        'c': t.c,
        'r': t.r,
      };

  static Token _tokenFromMap(final Map<String, dynamic> m) => Token(
        id: (m['id'] as String?) ?? '',
        team: _parseTeam(m['team'] as String?),
        c: (m['c'] as num?)?.toInt() ?? 0,
        r: (m['r'] as num?)?.toInt() ?? 0,
      );

  static Map<String, dynamic> _posToMap(final Pos p) =>
      <String, dynamic>{'c': p.c, 'r': p.r};

  static Pos _posFromMap(final Map<String, dynamic> m) => Pos(
        (m['c'] as num?)?.toInt() ?? 0,
        (m['r'] as num?)?.toInt() ?? 0,
      );

  static GamePhase _parsePhase(final String? raw) {
    for (final GamePhase p in GamePhase.values) {
      if (p.name == raw) return p;
    }
    return GamePhase.coinToss;
  }

  static Team _parseTeam(final String? raw) {
    if (raw == 'blue') return Team.blue;
    return Team.red;
  }
}

import 'dart:math' as math;

import 'package:mini_kickers/ai/ai_tuning.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/utils/game_logic.dart';

/// One token move the AI wants to play: which token to select, and
/// where to send it. The [AiController] (Day 3) translates this into
/// `SelectTokenEvent` → `MoveToEvent`.
class AiTokenMove {
  const AiTokenMove({required this.tokenId, required this.target});

  final String tokenId;
  final Pos target;

  @override
  bool operator ==(final Object other) =>
      other is AiTokenMove &&
      other.tokenId == tokenId &&
      other.target == target;

  @override
  int get hashCode => Object.hash(tokenId, target);

  @override
  String toString() =>
      'AiTokenMove(tokenId: $tokenId, target: ${target.c},${target.r})';
}

/// Heuristic AI brain. Pure decision-making — no bloc references, no
/// I/O, no SettingsService access (that's pre-resolved into [AiTuning]).
/// Hand it a [GameState] snapshot and it returns the chosen move.
///
/// **Scoring model** (see [docs/vs_ai_feature_spec.md] §3 for the full
/// derivation):
///
/// _Token moves_:
/// ```
/// score = w_chase_ball     · −distance(target, ball)
///       + w_capture_ball   ·  10 · (target == ball ? 1 : 0)
///       + w_block_opponent ·  (target adjacent to ball ? 1 : 0)
///       + noise(random_factor)
/// ```
///
/// _Ball moves_:
/// ```
/// score = w_push_to_goal   · −distance(target, opponent_goal_mouth)
///       + w_score_goal     ·  1 · (target ∈ goal_zone ? 1000 : 0)
///       + w_avoid_capture  · −1 · (opponent_token_adjacent_after ? 1 : 0)
///       + noise(random_factor)
/// ```
///
/// The noise term lets the same heuristic produce three felt
/// difficulty levels — see [_selectWithNoise] and §3.4 of the spec.
class AiPlayer {
  AiPlayer({
    required final AiTuning tuning,
    final math.Random? rng,
  })  : _tuning = tuning,
        _rng = rng ?? math.Random();

  final AiTuning _tuning;
  final math.Random _rng;

  // ── Public API ────────────────────────────────────────────────────────

  /// Returns the best legal token move for `state.turn`, or `null` if
  /// no token has any legal move (caller should let the bloc auto-skip
  /// the turn — the existing `RollDiceEvent` flow already handles this
  /// for human players).
  AiTokenMove? pickTokenMove(final GameState state) {
    final int? dice = state.dice;
    if (dice == null || dice <= 0) return null;

    final List<_ScoredTokenMove> scored = <_ScoredTokenMove>[];
    for (final Token t in state.tokens) {
      if (t.team != state.turn) continue;
      final List<Pos> reach = GameLogic.getReachable(
        tokens: state.tokens,
        turn: state.turn,
        sc: t.c,
        sr: t.r,
        steps: dice,
        isBall: false,
      );
      for (final Pos target in reach) {
        scored.add(_ScoredTokenMove(
          tokenId: t.id,
          target: target,
          score: _scoreTokenMove(state, target),
        ));
      }
    }
    if (scored.isEmpty) return null;

    final _ScoredTokenMove chosen = _selectWithNoise<_ScoredTokenMove>(
      scored,
      (final _ScoredTokenMove s) => s.score,
    );
    return AiTokenMove(tokenId: chosen.tokenId, target: chosen.target);
  }

  /// Returns the best legal ball move for `state.turn`, or `null` if
  /// no ball move is legal. Called when the AI has just captured the
  /// ball and the phase has transitioned to [GamePhase.moveBall].
  Pos? pickBallMove(final GameState state) {
    final int? dice = state.dice;
    if (dice == null || dice <= 0) return null;

    final List<Pos> reach = GameLogic.getReachable(
      tokens: state.tokens,
      turn: state.turn,
      sc: state.ball.c,
      sr: state.ball.r,
      steps: dice,
      isBall: true,
    );
    if (reach.isEmpty) return null;

    final List<_ScoredPos> scored = reach
        .map((final Pos p) =>
            _ScoredPos(target: p, score: _scoreBallMove(state, p)))
        .toList();

    final _ScoredPos chosen = _selectWithNoise<_ScoredPos>(
      scored,
      (final _ScoredPos s) => s.score,
    );
    return chosen.target;
  }

  // ── Token-move scoring ────────────────────────────────────────────────

  double _scoreTokenMove(final GameState state, final Pos target) {
    final Pos ball = state.ball;
    final int distToBall = _manhattan(target, ball);
    final bool capturing = target.c == ball.c && target.r == ball.r;
    // "Blocking" proxy: parking next to the ball without capturing it
    // (which gets its own bigger bonus). It denies the opponent an easy
    // capture next turn. Cheap heuristic; refine in tuning if needed.
    final bool blocking = !capturing && _manhattan(target, ball) == 1;

    return _tuning.weightChaseBall * (-distToBall.toDouble()) +
        _tuning.weightCaptureBall * (capturing ? 1.0 : 0.0) +
        _tuning.weightBlockOpponent * (blocking ? 1.0 : 0.0);
  }

  // ── Ball-move scoring ─────────────────────────────────────────────────

  double _scoreBallMove(final GameState state, final Pos target) {
    final Team turn = state.turn;
    // Red attacks the right edge (c = cols-1); Blue attacks c = 0.
    final int oppGoalCol = turn == Team.red ? GameConfig.cols - 1 : 0;

    final bool isGoal = (turn == Team.red &&
            target.c == GameConfig.cols - 1 &&
            target.r >= 2 &&
            target.r <= 4) ||
        (turn == Team.blue &&
            target.c == 0 &&
            target.r >= 2 &&
            target.r <= 4);

    // Distance to opponent's goal mouth — horizontal distance plus a
    // small vertical penalty if the ball is above/below the 3-cell
    // goal zone (rows 2-4). This makes the AI prefer ball moves that
    // both advance horizontally AND stay aligned with the goal.
    final int distToOppGoal =
        (target.c - oppGoalCol).abs() + _verticalGoalMisalignment(target);

    // Capture risk window: without lookahead, we only check the
    // adjacent (1-step) cells — i.e. "can the opponent capture by
    // rolling a 1?". With lookahead (Hard tier), we widen to 4 cells
    // — roughly the median dice value — which means "any opponent
    // token within plausible reach next turn". Same heuristic, just a
    // wider radius. Cheap, and a meaningful felt difficulty bump.
    final int captureRadius = _tuning.useLookahead ? 4 : 1;
    final bool willBeCaptured =
        _opponentWithinDistance(state, target, captureRadius);

    return _tuning.weightPushToGoal * (-distToOppGoal.toDouble()) +
        _tuning.weightScoreGoal * (isGoal ? 1.0 : 0.0) +
        _tuning.weightAvoidCapture * (willBeCaptured ? -1.0 : 0.0);
  }

  /// 0 if the ball is already in the 3-cell goal-mouth row range
  /// (rows 2-4); otherwise the row-distance to the nearest goal-mouth
  /// row.
  static int _verticalGoalMisalignment(final Pos p) {
    if (p.r >= 2 && p.r <= 4) return 0;
    if (p.r < 2) return 2 - p.r;
    return p.r - 4;
  }

  bool _opponentWithinDistance(
    final GameState state,
    final Pos p,
    final int radius,
  ) {
    final Team opp = state.turn == Team.red ? Team.blue : Team.red;
    for (final Token t in state.tokens) {
      if (t.team != opp) continue;
      if (_manhattan(p, Pos(t.c, t.r)) <= radius) return true;
    }
    return false;
  }

  // ── Selection with noise ──────────────────────────────────────────────

  /// Picks the candidate with the highest `score + noise`, where noise
  /// is uniform in `[-r, +r]` and `r = randomFactor × max(|score|)`.
  ///
  /// Scaling noise by the largest observed magnitude keeps the
  /// `random_factor` knob meaningful regardless of the absolute weight
  /// values: at `factor = 0`, no candidate ever overtakes the best;
  /// at `factor = 1`, any candidate can win.
  T _selectWithNoise<T>(
    final List<T> candidates,
    final double Function(T) scoreOf,
  ) {
    if (candidates.length == 1) return candidates.single;

    double maxAbs = 0;
    for (final T c in candidates) {
      final double a = scoreOf(c).abs();
      if (a > maxAbs) maxAbs = a;
    }
    // Guard against the all-zero case (e.g. identical candidates) so
    // we still get differentiation when randomFactor > 0.
    if (maxAbs == 0) maxAbs = 1.0;

    final double rf = _tuning.randomFactor;
    T? best;
    double bestNoisy = double.negativeInfinity;
    for (final T c in candidates) {
      final double noise = (_rng.nextDouble() * 2 - 1) * rf * maxAbs;
      final double noisy = scoreOf(c) + noise;
      if (noisy > bestNoisy) {
        bestNoisy = noisy;
        best = c;
      }
    }
    return best as T;
  }

  // ── Tiny helpers ──────────────────────────────────────────────────────

  static int _manhattan(final Pos a, final Pos b) =>
      (a.c - b.c).abs() + (a.r - b.r).abs();
}

class _ScoredTokenMove {
  const _ScoredTokenMove({
    required this.tokenId,
    required this.target,
    required this.score,
  });
  final String tokenId;
  final Pos target;
  final double score;
}

class _ScoredPos {
  const _ScoredPos({required this.target, required this.score});
  final Pos target;
  final double score;
}

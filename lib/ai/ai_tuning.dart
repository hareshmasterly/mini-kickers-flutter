import 'package:mini_kickers/data/services/settings_service.dart';

/// Plain-value bundle of the knobs the AI scoring code actually reads.
///
/// Why this exists: [AiPlayer] could read directly from
/// [SettingsService], but doing so would couple the heuristic logic to
/// a singleton with disk I/O and a Firestore dependency — awkward for
/// unit tests. By pulling values into an immutable tuning struct at
/// the top of each turn, the AI becomes a pure function of `(state,
/// tuning, rng)` that's trivial to test and reason about.
///
/// Construct via [AiTuning.fromSettings] in production, or
/// [AiTuning.test] in unit tests with explicit overrides.
class AiTuning {
  const AiTuning({
    required this.weightChaseBall,
    required this.weightCaptureBall,
    required this.weightBlockOpponent,
    required this.weightPushToGoal,
    required this.weightScoreGoal,
    required this.weightAvoidCapture,
    required this.randomFactor,
    required this.useLookahead,
  });

  // Token-move weights.
  final double weightChaseBall;
  final double weightCaptureBall;
  final double weightBlockOpponent;

  // Ball-move weights.
  final double weightPushToGoal;
  final double weightScoreGoal;
  final double weightAvoidCapture;

  /// 0.0 → fully deterministic (always picks highest-scoring move).
  /// 1.0 → pure noise (essentially random). See
  /// [docs/vs_ai_feature_spec.md] §3.4 for the calibration table.
  final double randomFactor;

  /// Hard-tier 1-ply opponent lookahead. Currently a no-op for token
  /// moves; will be wired up in Day 3 for ball moves.
  final bool useLookahead;

  /// Reads the live values from the [SettingsService] singleton.
  /// Resolves the user's current difficulty + remote overrides + safe
  /// defaults at call time, so the returned tuning is always a
  /// snapshot of "what the AI should do *right now*".
  factory AiTuning.fromSettings(final SettingsService s) => AiTuning(
        weightChaseBall: s.aiWeightChaseBall,
        weightCaptureBall: s.aiWeightCaptureBall,
        weightBlockOpponent: s.aiWeightBlockOpponent,
        weightPushToGoal: s.aiWeightPushToGoal,
        weightScoreGoal: s.aiWeightScoreGoal,
        weightAvoidCapture: s.aiWeightAvoidCapture,
        randomFactor: s.aiRandomFactor,
        useLookahead: s.aiUseLookahead,
      );

  /// Convenience constructor for unit tests. Defaults match the spec
  /// values; pass `randomFactor: 0` for deterministic move selection.
  factory AiTuning.test({
    final double weightChaseBall = 1.5,
    final double weightCaptureBall = 10.0,
    final double weightBlockOpponent = 0.8,
    final double weightPushToGoal = 1.0,
    final double weightScoreGoal = 1000.0,
    final double weightAvoidCapture = 0.5,
    final double randomFactor = 0.0,
    final bool useLookahead = false,
  }) =>
      AiTuning(
        weightChaseBall: weightChaseBall,
        weightCaptureBall: weightCaptureBall,
        weightBlockOpponent: weightBlockOpponent,
        weightPushToGoal: weightPushToGoal,
        weightScoreGoal: weightScoreGoal,
        weightAvoidCapture: weightAvoidCapture,
        randomFactor: randomFactor,
        useLookahead: useLookahead,
      );
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mini_kickers/ai/ai_player.dart';
import 'package:mini_kickers/ai/ai_tuning.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';

/// Minimal GameState builder for tests — sidesteps GameState.initial()
/// which calls SettingsService.instance.matchSeconds (not available in
/// pure unit tests). All non-test-relevant fields get safe defaults.
GameState _state({
  final List<Token>? tokens,
  final Pos ball = const Pos(5, 3),
  final Team turn = Team.blue,
  final int dice = 3,
  final GamePhase phase = GamePhase.move,
}) {
  return GameState(
    tokens: tokens ?? GameConfig.initialTokens(),
    ball: ball,
    turn: turn,
    phase: phase,
    dice: dice,
    selectedTokenId: null,
    highlights: const <Pos>[],
    redScore: 0,
    blueScore: 0,
    timeLeft: 900,
    isRolling: false,
    showGoalFlash: false,
    message: '',
  );
}

void main() {
  group('AiPlayer.pickTokenMove', () {
    test('returns null when dice is null', () {
      final AiPlayer ai = AiPlayer(
        tuning: AiTuning.test(),
        rng: math.Random(0),
      );
      final GameState s = _state(dice: 0).copyWith(dice: null);
      expect(ai.pickTokenMove(s), isNull);
    });

    test('returns null when no team token has a legal move', () {
      // Every blue token boxed in by red tokens AND board edges so no
      // legal move exists with dice=1. We surround b0 (9,2): it can't
      // step (10,2)=edge-but-non-goal-OK actually wait — let me just
      // give Blue dice=0 effectively. Easier: use dice=0 → no moves.
      final AiPlayer ai = AiPlayer(
        tuning: AiTuning.test(),
        rng: math.Random(0),
      );
      // dice=0 means getReachable returns the start cell only, which is
      // occupied → filtered out → empty result for every token.
      final GameState s = _state(dice: 0);
      expect(ai.pickTokenMove(s), isNull);
    });

    test('captures the ball when reachable in exactly N steps', () {
      // Custom layout: a Blue token at (5,5) can reach the ball at
      // (5,3) in 2 cardinal steps. randomFactor=0 → fully deterministic.
      final List<Token> tokens = <Token>[
        const Token(id: 'r0', team: Team.red, c: 1, r: 2),
        const Token(id: 'r1', team: Team.red, c: 1, r: 3),
        const Token(id: 'r2', team: Team.red, c: 1, r: 4),
        const Token(id: 'b0', team: Team.blue, c: 5, r: 5), // 2 steps from ball
        const Token(id: 'b1', team: Team.blue, c: 9, r: 0),
        const Token(id: 'b2', team: Team.blue, c: 9, r: 6),
      ];
      final AiPlayer ai = AiPlayer(
        tuning: AiTuning.test(),
        rng: math.Random(0),
      );
      final GameState s = _state(
        tokens: tokens,
        ball: const Pos(5, 3),
        turn: Team.blue,
        dice: 2,
      );

      final AiTokenMove? move = ai.pickTokenMove(s);
      expect(move, isNotNull);
      expect(move!.tokenId, 'b0');
      expect(move.target, const Pos(5, 3));
    });

    test('moves toward the ball when capture not available', () {
      // Blue token at (8,3), ball at (5,3), dice=2. Token can't reach
      // ball in 2 steps (distance 3). Best move: get closer → (6,3).
      final List<Token> tokens = <Token>[
        const Token(id: 'r0', team: Team.red, c: 1, r: 2),
        const Token(id: 'r1', team: Team.red, c: 1, r: 3),
        const Token(id: 'r2', team: Team.red, c: 1, r: 4),
        const Token(id: 'b0', team: Team.blue, c: 8, r: 3),
        const Token(id: 'b1', team: Team.blue, c: 9, r: 0),
        const Token(id: 'b2', team: Team.blue, c: 9, r: 6),
      ];
      final AiPlayer ai = AiPlayer(
        tuning: AiTuning.test(),
        rng: math.Random(0),
      );
      final GameState s = _state(
        tokens: tokens,
        ball: const Pos(5, 3),
        turn: Team.blue,
        dice: 2,
      );

      final AiTokenMove? move = ai.pickTokenMove(s);
      expect(move, isNotNull);
      expect(move!.tokenId, 'b0');
      // (6,3) is the closest reachable cell to the ball.
      expect(move.target, const Pos(6, 3));
    });

    test('deterministic with same seed', () {
      final List<Token> tokens = GameConfig.initialTokens();
      final GameState s = _state(tokens: tokens, dice: 3, turn: Team.blue);

      final AiPlayer a = AiPlayer(
        tuning: AiTuning.test(randomFactor: 0.5),
        rng: math.Random(42),
      );
      final AiPlayer b = AiPlayer(
        tuning: AiTuning.test(randomFactor: 0.5),
        rng: math.Random(42),
      );
      expect(a.pickTokenMove(s), equals(b.pickTokenMove(s)));
    });

    test('high random factor varies decisions across seeds', () {
      // With randomFactor = 1.0, different seeds should produce
      // different moves at least some of the time. We just check that
      // not ALL seeds produce the same move (i.e. randomness has any
      // effect at all).
      final List<Token> tokens = GameConfig.initialTokens();
      final GameState s = _state(tokens: tokens, dice: 3, turn: Team.blue);

      final Set<AiTokenMove> seen = <AiTokenMove>{};
      for (int seed = 0; seed < 20; seed++) {
        final AiPlayer ai = AiPlayer(
          tuning: AiTuning.test(randomFactor: 1.0),
          rng: math.Random(seed),
        );
        final AiTokenMove? m = ai.pickTokenMove(s);
        if (m != null) seen.add(m);
      }
      expect(seen.length, greaterThan(1),
          reason: 'High randomFactor should produce more than one outcome '
              'across 20 different seeds');
    });
  });

  group('AiPlayer.pickBallMove', () {
    test('picks the goal cell when reachable', () {
      // Blue has the ball at (1,3) — one step from its target goal at
      // (0,3). dice=1 → reachable.
      final AiPlayer ai = AiPlayer(
        tuning: AiTuning.test(),
        rng: math.Random(0),
      );
      final GameState s = _state(
        ball: const Pos(1, 3),
        turn: Team.blue,
        dice: 1,
        phase: GamePhase.moveBall,
      );
      final Pos? move = ai.pickBallMove(s);
      expect(move, const Pos(0, 3));
    });

    test('advances toward opponent goal otherwise', () {
      // Blue ball at (5,3), dice=1. No goal reachable. Should move
      // closer to Blue's target (col 0) → (4,3).
      final AiPlayer ai = AiPlayer(
        tuning: AiTuning.test(),
        rng: math.Random(0),
      );
      final GameState s = _state(
        ball: const Pos(5, 3),
        turn: Team.blue,
        dice: 1,
        phase: GamePhase.moveBall,
      );
      final Pos? move = ai.pickBallMove(s);
      expect(move, const Pos(4, 3));
    });

    test('returns null when no legal ball move exists', () {
      final AiPlayer ai = AiPlayer(
        tuning: AiTuning.test(),
        rng: math.Random(0),
      );
      // dice=0 → reach is empty (start cell is "occupied" by the ball).
      final GameState s = _state(
        ball: const Pos(5, 3),
        turn: Team.blue,
        dice: 0,
        phase: GamePhase.moveBall,
      );
      expect(ai.pickBallMove(s), isNull);
    });

    test('lookahead increases avoid-capture penalty radius', () {
      // Blue has the ball at (5,3). dice=2. Two reachable ball moves:
      //   A: (3,3) — 2 cells closer to Blue's goal at col 0
      //   B: (5,1) — 2 cells away vertically (no horizontal progress)
      // A red token sits at (1,3), 2 cells from (3,3) — within the
      // lookahead radius of 4 but outside the no-lookahead radius of 1.
      // With lookahead OFF: A wins (closer to goal, no adjacency
      // penalty since red is 2 cells away from A).
      // With lookahead ON: A is penalised (red within radius 4) so B
      // becomes more attractive. Hard avoid-capture weight needs to
      // outweigh the goal-distance benefit for B to win, so use a
      // strong avoid-capture weight in this test.
      final List<Token> tokens = <Token>[
        const Token(id: 'r0', team: Team.red, c: 1, r: 3),
        const Token(id: 'r1', team: Team.red, c: 0, r: 0),
        const Token(id: 'r2', team: Team.red, c: 0, r: 6),
        const Token(id: 'b0', team: Team.blue, c: 9, r: 0),
        const Token(id: 'b1', team: Team.blue, c: 9, r: 3),
        const Token(id: 'b2', team: Team.blue, c: 9, r: 6),
      ];
      final GameState s = _state(
        tokens: tokens,
        ball: const Pos(5, 3),
        turn: Team.blue,
        dice: 2,
        phase: GamePhase.moveBall,
      );

      // No lookahead: AI happily moves ball to (3,3).
      final AiPlayer noLookahead = AiPlayer(
        tuning: AiTuning.test(weightAvoidCapture: 5.0),
        rng: math.Random(0),
      );
      expect(noLookahead.pickBallMove(s), const Pos(3, 3));

      // Lookahead ON: red token within radius 4 → AI avoids (3,3) and
      // picks a safer cell.
      final AiPlayer withLookahead = AiPlayer(
        tuning: AiTuning.test(
          weightAvoidCapture: 5.0,
          useLookahead: true,
        ),
        rng: math.Random(0),
      );
      expect(withLookahead.pickBallMove(s), isNot(const Pos(3, 3)));
    });
  });
}

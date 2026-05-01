import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/commentary_helper.dart';
import 'package:mini_kickers/utils/game_logic.dart';

part 'game_bloc.freezed.dart';
part 'game_event.dart';
part 'game_state.dart';

class GameBloc extends Bloc<GameEvent, GameState> {
  GameBloc() : super(GameState.initial()) {
    on<InitialEvent>(_onInitial);
    on<RollDiceEvent>(_onRollDice);
    on<DiceRolledEvent>(_onDiceRolled);
    on<SelectTokenEvent>(_onSelectToken);
    on<MoveToEvent>(_onMoveTo);
    on<BallRolledEvent>(_onBallRolled);
    on<NextTurnEvent>(_onNextTurn);
    on<TickEvent>(_onTick);
    on<ResetGameEvent>(_onReset);
    on<GoalFlashClearEvent>(_onGoalFlashClear);
    on<CoinTossCompleteEvent>(_onCoinTossComplete);
    on<RefreshSettingsEvent>(_onRefreshSettings);

    _startTimer();
  }

  final Random _rng = Random();
  Timer? _matchTimer;

  void _startTimer() {
    _matchTimer?.cancel();
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (final _) {
      add(const TickEvent());
    });
  }

  Future<void> _onInitial(
    final InitialEvent event,
    final Emitter<GameState> emit,
  ) async {
    emit(GameState.initial().copyWith(
      message: CommentaryHelper.pick(CommentaryHelper.gameStart),
    ));
  }

  void _onTick(final TickEvent event, final Emitter<GameState> emit) {
    if (state.phase == GamePhase.gameOver ||
        state.phase == GamePhase.coinToss) {
      return;
    }
    final int next = state.timeLeft - 1;
    if (next <= 0) {
      final int r = state.redScore;
      final int b = state.blueScore;
      final String winner = r > b
          ? CommentaryHelper.pick(CommentaryHelper.winRed)
          : b > r
              ? CommentaryHelper.pick(CommentaryHelper.winBlue)
              : CommentaryHelper.pick(CommentaryHelper.draw);
      emit(state.copyWith(
        timeLeft: 0,
        phase: GamePhase.gameOver,
        message: '${CommentaryHelper.pick(CommentaryHelper.gameEnd)} $winner',
      ));
      return;
    }
    emit(state.copyWith(timeLeft: next));
  }

  Future<void> _onRollDice(
    final RollDiceEvent event,
    final Emitter<GameState> emit,
  ) async {
    if (state.phase != GamePhase.roll || state.isRolling) return;
    AudioHelper.diceRoll();
    emit(state.copyWith(
      isRolling: true,
      message: CommentaryHelper.pick(CommentaryHelper.rolling),
    ));

    await Future<void>.delayed(const Duration(milliseconds: 1200));

    final int d = _rng.nextInt(6) + 1;
    add(DiceRolledEvent(diceValue: d));
  }

  Future<void> _onDiceRolled(
    final DiceRolledEvent event,
    final Emitter<GameState> emit,
  ) async {
    AudioHelper.diceResult();
    final int d = event.diceValue;
    final bool canMove = GameLogic.teamHasAnyMove(
      tokens: state.tokens,
      turn: state.turn,
      dice: d,
      ball: state.ball,
    );

    if (!canMove) {
      AudioHelper.noMoves();
      emit(state.copyWith(
        dice: d,
        phase: GamePhase.move,
        isRolling: false,
        highlights: const <Pos>[],
        selectedTokenId: null,
        message: CommentaryHelper.pick(
          CommentaryHelper.noMoves,
          vars: <String, String>{
            'other': CommentaryHelper.otherLabel(state.turn),
          },
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      add(const NextTurnEvent());
      return;
    }

    final List<String> pool = d >= 5
        ? CommentaryHelper.highRoll
        : d <= 2
            ? CommentaryHelper.lowRoll
            : CommentaryHelper.midRoll;

    emit(state.copyWith(
      dice: d,
      phase: GamePhase.move,
      isRolling: false,
      highlights: const <Pos>[],
      selectedTokenId: null,
      message: CommentaryHelper.pick(
        pool,
        vars: <String, String>{
          'd': '$d',
          'team': CommentaryHelper.teamLabel(state.turn),
        },
      ),
    ));
  }

  void _onSelectToken(
    final SelectTokenEvent event,
    final Emitter<GameState> emit,
  ) {
    if (state.phase != GamePhase.move) return;
    final Token? t = state.tokens.where((final Token x) => x.id == event.id).firstOrNull;
    if (t == null || t.team != state.turn) return;
    final List<Pos> reachable = GameLogic.getReachable(
      tokens: state.tokens,
      turn: state.turn,
      sc: t.c,
      sr: t.r,
      steps: state.dice!,
      isBall: false,
      ball: state.ball,
    );

    // ── DEBUG TRACE ──
    // Logs the full input + output of the move-rules engine. Compiled
    // out in release. Use this to confirm the algorithm is producing
    // exactly the cells we expect for a given dice value.
    if (kDebugMode) {
      final String tokenList = state.tokens
          .map((final Token x) => '${x.id}@(${x.c},${x.r})')
          .join(' ');
      final String reachStr = reachable
          .map((final Pos p) => '(${p.c},${p.r})')
          .join(', ');
      debugPrint(
        'GameBloc.selectToken | dice=${state.dice} '
        'sel=${t.id}@(${t.c},${t.r}) | tokens=[$tokenList] | '
        'reachable(${reachable.length})=[$reachStr]',
      );
    }

    if (reachable.isEmpty) {
      emit(state.copyWith(message: "That one's blocked — try another!"));
      return;
    }
    AudioHelper.select();
    emit(state.copyWith(
      selectedTokenId: event.id,
      highlights: reachable,
      message: CommentaryHelper.pick(
        CommentaryHelper.selectToken,
        vars: <String, String>{'team': CommentaryHelper.teamLabel(state.turn)},
      ),
    ));
  }

  Future<void> _onMoveTo(
    final MoveToEvent event,
    final Emitter<GameState> emit,
  ) async {
    // ── Strict guard: target MUST be one of the cells the rules engine
    // (`getReachable`) currently produced. This enforces:
    //   1. exact dice steps (no stopping early, no overshoot)
    //   2. cardinal-only movement (no diagonals / "cross")
    //   3. no revisits within the same path
    //   4. no landing on occupied / goal-area / out-of-board cells
    // The UI already only renders highlights for legal cells, but this
    // makes the bloc the single source of truth — any stale tap, double-
    // tap, or out-of-band event is silently rejected here.
    final Pos target = Pos(event.c, event.r);
    if (!state.highlights.contains(target)) return;

    if (state.phase == GamePhase.move) {
      final String? selectedId = state.selectedTokenId;
      if (selectedId == null) return;
      final List<Token> updatedTokens = state.tokens
          .map((final Token t) => t.id == selectedId
              ? t.copyWith(c: event.c, r: event.r)
              : t)
          .toList();

      final bool landedOnBall =
          state.ball.c == event.c && state.ball.r == event.r;

      if (landedOnBall) {
        AudioHelper.ballControl();
        emit(state.copyWith(
          tokens: updatedTokens,
          highlights: const <Pos>[],
          selectedTokenId: null,
          isRolling: true,
          message: CommentaryHelper.pick(
            CommentaryHelper.ballControl,
            vars: <String, String>{
              'team': CommentaryHelper.teamLabel(state.turn),
            },
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        final int d2 = _rng.nextInt(6) + 1;
        add(BallRolledEvent(diceValue: d2));
      } else {
        AudioHelper.tokenMove();
        emit(state.copyWith(
          tokens: updatedTokens,
          highlights: const <Pos>[],
          selectedTokenId: null,
          message: CommentaryHelper.pick(
            CommentaryHelper.tokenMoved,
            vars: <String, String>{
              'team': CommentaryHelper.teamLabel(state.turn),
            },
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        add(const NextTurnEvent());
      }
    } else if (state.phase == GamePhase.moveBall) {
      final Pos newBall = Pos(event.c, event.r);
      final bool scored =
          GameLogic.isGoalScored(ball: newBall, turn: state.turn);

      if (scored) {
        AudioHelper.goal();
        final int newRed =
            state.turn == Team.red ? state.redScore + 1 : state.redScore;
        final int newBlue =
            state.turn == Team.blue ? state.blueScore + 1 : state.blueScore;
        emit(state.copyWith(
          ball: newBall,
          highlights: const <Pos>[],
          redScore: newRed,
          blueScore: newBlue,
          showGoalFlash: true,
          message: CommentaryHelper.pick(
            CommentaryHelper.goal,
            vars: <String, String>{
              'team': CommentaryHelper.teamLabel(state.turn),
            },
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 1400));
        add(const GoalFlashClearEvent());
        return;
      }

      AudioHelper.ballMove();
      emit(state.copyWith(
        ball: newBall,
        highlights: const <Pos>[],
        message: CommentaryHelper.pick(
          CommentaryHelper.ballMoved,
          vars: <String, String>{
            'team': CommentaryHelper.teamLabel(state.turn),
          },
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      add(const NextTurnEvent());
    }
  }

  void _onBallRolled(
    final BallRolledEvent event,
    final Emitter<GameState> emit,
  ) {
    AudioHelper.diceResult();
    final List<Pos> reach = GameLogic.getReachable(
      tokens: state.tokens,
      turn: state.turn,
      sc: state.ball.c,
      sr: state.ball.r,
      steps: event.diceValue,
      isBall: true,
    );
    emit(state.copyWith(
      dice: event.diceValue,
      phase: GamePhase.moveBall,
      highlights: reach,
      isRolling: false,
      message: 'Now move the ball! Rolled a ${event.diceValue}!',
    ));
  }

  void _onGoalFlashClear(
    final GoalFlashClearEvent event,
    final Emitter<GameState> emit,
  ) {
    final int redScore = state.redScore;
    final int blueScore = state.blueScore;
    final int timeLeft = state.timeLeft;
    final Team scorer = state.turn;
    final Team kicker = scorer == Team.red ? Team.blue : Team.red;
    final GameState reset = GameState.initial().copyWith(
      redScore: redScore,
      blueScore: blueScore,
      timeLeft: timeLeft,
      showGoalFlash: false,
      phase: GamePhase.roll,
      turn: kicker,
      message: CommentaryHelper.pick(
        CommentaryHelper.resetBoard,
        vars: <String, String>{
          'other': CommentaryHelper.teamLabel(kicker),
        },
      ),
    );
    emit(reset);
  }

  void _onNextTurn(
    final NextTurnEvent event,
    final Emitter<GameState> emit,
  ) {
    AudioHelper.turnSwitch();
    emit(state.copyWith(
      turn: state.turn == Team.red ? Team.blue : Team.red,
      phase: GamePhase.roll,
      dice: null,
      selectedTokenId: null,
      highlights: const <Pos>[],
    ));
  }

  void _onReset(
    final ResetGameEvent event,
    final Emitter<GameState> emit,
  ) {
    emit(GameState.initial());
    _startTimer();
  }

  void _onRefreshSettings(
    final RefreshSettingsEvent event,
    final Emitter<GameState> emit,
  ) {
    // Only safe to update timeLeft live if game hasn't started (still on toss)
    // or we're already in a fresh state.
    if (state.phase == GamePhase.coinToss) {
      emit(state.copyWith(
        timeLeft: SettingsService.instance.matchSeconds,
      ));
    }
  }

  void _onCoinTossComplete(
    final CoinTossCompleteEvent event,
    final Emitter<GameState> emit,
  ) {
    emit(state.copyWith(
      phase: GamePhase.roll,
      turn: event.winner,
      message: CommentaryHelper.pick(
        CommentaryHelper.gameStart,
        vars: <String, String>{
          'team': CommentaryHelper.teamLabel(event.winner),
        },
      ),
    ));
  }

  String get formattedTime {
    final String m = (state.timeLeft ~/ 60).toString();
    final String s = (state.timeLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Future<void> close() {
    _matchTimer?.cancel();
    return super.close();
  }
}

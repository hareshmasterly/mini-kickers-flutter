import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/models/online_context.dart';
import 'package:mini_kickers/data/models/online_match.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/commentary_helper.dart';
import 'package:mini_kickers/utils/game_logic.dart';

part 'game_bloc.freezed.dart';
part 'game_event.dart';
part 'game_state.dart';

/// Callback shape used by [OnlineGameController] to push every
/// locally-initiated state change to Firestore. The bloc invokes it
/// from `onTransition` for all events EXCEPT [ApplyRemoteStateEvent]
/// — that filter is what keeps the two clients from echoing each
/// other's state back and forth in an infinite loop.
typedef GameStatePushHook = void Function(GameState newState);

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
    on<ApplyRemoteStateEvent>(_onApplyRemoteState);
    on<AttachOnlineContextEvent>(_onAttachOnlineContext);

    _startTimer();
  }

  final Random _rng = Random();
  Timer? _matchTimer;

  /// Installed by [OnlineGameController] right after it dispatches the
  /// initial [AttachOnlineContextEvent]. While set, [onTransition]
  /// invokes it for every state change EXCEPT those triggered by
  /// [ApplyRemoteStateEvent] (which already came from the wire and
  /// must not be echoed back).
  ///
  /// Cleared on dispose by the controller — the bloc itself never
  /// touches it directly so local play has zero overhead.
  GameStatePushHook? _pushHook;

  /// Setter used by [OnlineGameController]. Public on purpose so
  /// the controller doesn't need a backdoor; it's still a no-op
  /// when no controller is attached.
  set pushHook(final GameStatePushHook? hook) => _pushHook = hook;

  /// Override called by the bloc framework after every emit. We use
  /// it as the single chokepoint for "tell the OnlineGameController
  /// about a new state worth syncing." The [ApplyRemoteStateEvent]
  /// guard is what prevents the two clients from ping-ponging the
  /// same state back and forth.
  @override
  void onTransition(final Transition<GameEvent, GameState> transition) {
    super.onTransition(transition);
    if (_pushHook == null) return;
    if (transition.event is ApplyRemoteStateEvent) return;
    if (transition.event is AttachOnlineContextEvent) return;
    _pushHook!(transition.nextState);
  }

  /// Returns true when the action should be IGNORED because we're in
  /// online mode and it's the opposite player's turn. Local play is
  /// unaffected (no online context → always returns false).
  bool _shouldIgnoreLocalAction() {
    final OnlineContext? online = state.online;
    if (online == null) return false;
    return !online.isLocalTurn(state.turn);
  }

  void _startTimer() {
    _matchTimer?.cancel();
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (final _) {
      add(const TickEvent());
    });
  }

  /// Pause the match countdown without changing any game state. Used
  /// from the game screen when an ad overlay (Amazon promo, paid
  /// interstitial, restart interstitial) covers the board — without
  /// this, the user keeps "losing" match seconds while looking at an
  /// ad they didn't ask to be there.
  ///
  /// Idempotent: calling [pauseTimer] when already paused is a no-op.
  void pauseTimer() {
    _matchTimer?.cancel();
    _matchTimer = null;
  }

  /// Resume the match countdown after a [pauseTimer]. No-op if the
  /// timer is already running. Safe to call from any phase.
  void resumeTimer() {
    if (_matchTimer != null) return;
    _startTimer();
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
    // Online: only the active-team client decrements + pushes the
    // shared clock. The inactive client receives `time_left` updates
    // via the remote sync stream, so its UI still counts down — just
    // driven by the wire instead of a local timer. Without this gate
    // both clients would write to `time_left` every second and race.
    if (_shouldIgnoreLocalAction()) return;
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
    // Online: only the active-team player rolls. The opposite client
    // observes `is_rolling: true` followed by the dice value via the
    // remote sync stream and runs the same animation.
    if (_shouldIgnoreLocalAction()) return;
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
        // Per-team dice mirrors the shared `dice` for the active side
        // only — the inactive side keeps its previous value so its
        // panel's cube stops "ghost-updating".
        redDice: state.turn == Team.red ? d : state.redDice,
        blueDice: state.turn == Team.blue ? d : state.blueDice,
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
      // Per-team dice mirrors `dice` for the active side only.
      redDice: state.turn == Team.red ? d : state.redDice,
      blueDice: state.turn == Team.blue ? d : state.blueDice,
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
    // Online: only the active player can pick a token. Stops the
    // inactive client's stale taps from changing the highlight set.
    if (_shouldIgnoreLocalAction()) return;
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
    // Online: only the active-side client commits the move. The
    // opposite side observes the resulting state via the remote sync
    // stream — its own MoveTo events are dropped here.
    if (_shouldIgnoreLocalAction()) return;
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
      // Same per-team mirror as the regular roll handler — the active
      // side's panel-cube updates, the inactive side stays put.
      redDice:
          state.turn == Team.red ? event.diceValue : state.redDice,
      blueDice:
          state.turn == Team.blue ? event.diceValue : state.blueDice,
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
    // Online: the kickoff team is decided server-side at match
    // creation (see MatchService._initialMatchMap) and arrives via
    // ApplyRemoteState as `state.turn`. The coin-toss UI on each
    // client must animate to that same predetermined value rather
    // than rolling its own Random — otherwise the two clients would
    // disagree about who kicks off. We honour `event.winner` here
    // either way: in local play it's whatever the local widget
    // picked; in online play the widget is fed `state.turn` so the
    // value matches what's already on the doc.
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

  /// Online-1v1: replace the local state wholesale with whatever
  /// arrived via the wire. Called by [OnlineGameController] on every
  /// `matches/{id}` snapshot that wasn't initiated by us.
  ///
  /// We intentionally DON'T copy the local `online` field from the
  /// inbound state — the [OnlineContext] is purely client-side
  /// (it embeds our own uid + team) and never round-trips through
  /// Firestore. Instead we keep whichever context the bloc already
  /// has from the prior [AttachOnlineContextEvent].
  void _onApplyRemoteState(
    final ApplyRemoteStateEvent event,
    final Emitter<GameState> emit,
  ) {
    final OnlineMatch m = event.match;
    emit(GameState(
      tokens: m.tokens,
      ball: m.ball,
      turn: m.turn,
      phase: m.phase,
      dice: m.dice,
      redDice: m.redDice,
      blueDice: m.blueDice,
      selectedTokenId: m.selectedTokenId,
      highlights: m.highlights,
      redScore: m.redScore,
      blueScore: m.blueScore,
      timeLeft: m.timeLeft,
      isRolling: m.isRolling,
      showGoalFlash: m.showGoalFlash,
      message: m.message,
      online: event.context,
    ));
  }

  /// Online-1v1: install or clear the [OnlineContext] without
  /// touching any other field. Called once at match start by
  /// [OnlineGameController.start] (with a non-null context) and
  /// once on dispose (with null).
  void _onAttachOnlineContext(
    final AttachOnlineContextEvent event,
    final Emitter<GameState> emit,
  ) {
    emit(state.copyWith(online: event.context));
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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mini_kickers/ai/ai_player.dart';
import 'package:mini_kickers/ai/ai_tuning.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';

/// Drives the AI side of a VS AI match.
///
/// Listens to [GameBloc] state changes and, whenever it's the AI's turn
/// in a phase the AI can act on (`roll` / `move` / `moveBall`), waits
/// the configured "thinking" delay and then dispatches the appropriate
/// events to the bloc:
///
///   • `phase == roll`     → fires [RollDiceEvent]
///   • `phase == move`     → picks a token via [AiPlayer.pickTokenMove]
///                           and fires [SelectTokenEvent] + [MoveToEvent]
///   • `phase == moveBall` → picks a ball target via
///                           [AiPlayer.pickBallMove] and fires
///                           [MoveToEvent]
///
/// **Lifecycle**: instantiate with [start()] when [GameMode.vsAi] is
/// active, call [dispose()] when leaving the game screen. Reusable
/// across matches — handles `coinToss` / `gameOver` resets cleanly.
///
/// **Tuning refresh**: a new [AiPlayer] is rebuilt at the top of each
/// AI turn, so changes to difficulty made via Settings mid-match take
/// effect on the very next turn.
class AiController {
  AiController({
    required final GameBloc bloc,
    final Team aiTeam = Team.blue,
  })  : _bloc = bloc,
        _aiTeam = aiTeam;

  final GameBloc _bloc;
  final Team _aiTeam;

  StreamSubscription<GameState>? _sub;
  Timer? _delayTimer;
  AiPlayer _player = AiPlayer(tuning: AiTuning.test());

  /// How long highlights for the AI's chosen token stay visible BEFORE
  /// the AI commits the move. Without this, [SelectTokenEvent] and
  /// [MoveToEvent] fire back-to-back in the same handler tick — the
  /// player just sees the token teleport, never the highlights, and
  /// has no idea what the AI considered.
  static const Duration _highlightLinger = Duration(milliseconds: 700);

  /// True between "scheduled to act" and "acted" — guards against
  /// re-entry when state events fire mid-delay (e.g. `TickEvent` every
  /// second decrements `timeLeft` and triggers `_onState`).
  bool _acting = false;

  /// True while the game UI is showing an ad overlay (Amazon promo
  /// or paid interstitial). The AI must not roll/move/kick under a
  /// covering overlay — without this gate it acts invisibly while the
  /// player is still looking at the ad, and they return to a board
  /// that's already mid-AI-turn with no idea what just happened.
  ///
  /// Set via [pause]/[resume] from the game screen as overlays show
  /// and dismiss.
  bool _paused = false;

  /// Begin listening. Idempotent.
  void start() {
    if (_sub != null) return;
    _sub = _bloc.stream.listen(_onState);
    // Trigger immediately for the current state in case we mounted
    // mid-turn (e.g. AI went first via coin toss).
    _onState(_bloc.state);
  }

  /// Pause AI activity. Cancels any pending action and prevents new
  /// ones from being scheduled until [resume] is called. Call this
  /// from the game screen when an ad overlay (Amazon promo or paid
  /// interstitial) appears so the AI doesn't sneak in a turn behind
  /// the user's back.
  void pause() {
    _paused = true;
    _delayTimer?.cancel();
    _delayTimer = null;
    _acting = false;
  }

  /// Resume AI activity. Re-evaluates the current bloc state and
  /// schedules an action if it's the AI's turn — so the AI doesn't
  /// have to wait for the next state change to "wake up".
  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_sub != null) _onState(_bloc.state);
  }

  /// Stop listening + cancel any pending action. Safe to call
  /// multiple times.
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _delayTimer?.cancel();
    _delayTimer = null;
    _acting = false;
    _paused = false;
  }

  // ── State handler ─────────────────────────────────────────────────────

  void _onState(final GameState state) {
    // Reset on match boundaries: cancel any pending action and clear
    // the acting flag so a fresh match starts cleanly. Without this,
    // a Restart mid-AI-turn would leave `_acting=true` stuck and the
    // AI would never act again until app restart.
    if (state.phase == GamePhase.coinToss ||
        state.phase == GamePhase.gameOver) {
      _delayTimer?.cancel();
      _delayTimer = null;
      _acting = false;
      return;
    }

    if (_acting) return;
    if (!_shouldAct(state)) {
      _delayTimer?.cancel();
      _delayTimer = null;
      return;
    }

    // Refresh tuning at the top of each turn so user difficulty changes
    // (or remote re-tunings) take effect on the very next AI move.
    _player = AiPlayer(
      tuning: AiTuning.fromSettings(SettingsService.instance),
    );

    _acting = true;
    final Duration delay = Duration(
      milliseconds: SettingsService.instance.aiThinkDelayMs,
    );
    _delayTimer = Timer(delay, _onDelayElapsed);
  }

  bool _shouldAct(final GameState state) {
    if (_paused) return false;
    if (state.turn != _aiTeam) return false;
    if (state.isRolling) return false;
    return state.phase == GamePhase.roll ||
        state.phase == GamePhase.move ||
        state.phase == GamePhase.moveBall;
  }

  /// Re-resolves the action against the *current* bloc state (not a
  /// snapshot from when the timer was scheduled). This way, if the bloc
  /// transitioned during the delay (e.g. user pressed Restart), we
  /// either skip the action or pick a fresh move based on the new
  /// state.
  void _onDelayElapsed() {
    _acting = false;
    final GameState state = _bloc.state;
    if (!_shouldAct(state)) return;

    switch (state.phase) {
      case GamePhase.roll:
        if (kDebugMode) debugPrint('AiController: rolling dice');
        _bloc.add(const RollDiceEvent());
        break;
      case GamePhase.move:
        final AiTokenMove? move = _player.pickTokenMove(state);
        if (move == null) {
          if (kDebugMode) {
            debugPrint('AiController: no token move available — '
                'bloc auto-skip will handle it');
          }
          return;
        }
        if (kDebugMode) {
          debugPrint('AiController: token ${move.tokenId} → '
              '(${move.target.c},${move.target.r})');
        }
        _bloc.add(SelectTokenEvent(id: move.tokenId));
        // Hold the "acting" flag through the SelectToken state event
        // AND the highlight-linger delay so:
        //   1. The intermediate state (selectedTokenId set,
        //      highlights computed) doesn't re-trigger _onState into
        //      scheduling another action.
        //   2. The user gets ~700 ms to see the highlights animate
        //      in before the AI commits the move — without this,
        //      tokens just teleported and the AI felt opaque.
        _acting = true;
        _delayTimer = Timer(_highlightLinger, () {
          _acting = false;
          if (!_shouldAct(_bloc.state)) return;
          _bloc.add(MoveToEvent(c: move.target.c, r: move.target.r));
        });
        break;
      case GamePhase.moveBall:
        final Pos? target = _player.pickBallMove(state);
        if (target == null) {
          if (kDebugMode) debugPrint('AiController: no ball move available');
          return;
        }
        if (kDebugMode) {
          debugPrint('AiController: ball → (${target.c},${target.r})');
        }
        // Ball-move highlights were already painted when the bloc
        // transitioned into [GamePhase.moveBall] (during BallRolled),
        // so the player's been looking at them throughout the
        // aiThinkDelayMs we already burned. No additional linger
        // needed here.
        _bloc.add(MoveToEvent(c: target.c, r: target.r));
        break;
      case GamePhase.coinToss:
      case GamePhase.gameOver:
        // Already filtered by `_shouldAct`; included for switch
        // exhaustiveness.
        break;
    }
  }
}

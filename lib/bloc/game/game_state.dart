part of 'game_bloc.dart';

@freezed
abstract class GameState with _$GameState {
  const factory GameState({
    required final List<Token> tokens,
    required final Pos ball,
    required final Team turn,
    required final GamePhase phase,

    /// The CURRENT roll's dice value — set when the active team rolls,
    /// cleared at NextTurn. Used by move-engine logic (`state.dice!`)
    /// and the debug overlay. Not the right field for per-side UI
    /// display (use [redDice] / [blueDice] for that).
    required final int? dice,

    /// Last value rolled by Red (persists across turns). The LEFT side
    /// panel reads this so its dice keeps showing Red's last number
    /// even while Blue is taking their turn — without it, both panels
    /// were "ghost-updating" off the shared [dice] field.
    required final int? redDice,

    /// Last value rolled by Blue. Mirror of [redDice] for the RIGHT
    /// side panel.
    required final int? blueDice,

    required final String? selectedTokenId,
    required final List<Pos> highlights,
    required final int redScore,
    required final int blueScore,
    required final int timeLeft,
    required final bool isRolling,
    required final bool showGoalFlash,
    required final String message,
  }) = _GameState;

  factory GameState.initial() => GameState(
        tokens: GameConfig.initialTokens(),
        ball: GameConfig.initialBall,
        turn: Team.red,
        phase: GamePhase.coinToss,
        dice: null,
        redDice: null,
        blueDice: null,
        selectedTokenId: null,
        highlights: const <Pos>[],
        redScore: 0,
        blueScore: 0,
        timeLeft: SettingsService.instance.matchSeconds,
        isRolling: false,
        showGoalFlash: false,
        message: 'Toss the coin to decide who kicks off!',
      );
}

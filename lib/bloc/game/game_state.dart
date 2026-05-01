part of 'game_bloc.dart';

@freezed
abstract class GameState with _$GameState {
  const factory GameState({
    required final List<Token> tokens,
    required final Pos ball,
    required final Team turn,
    required final GamePhase phase,
    required final int? dice,
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

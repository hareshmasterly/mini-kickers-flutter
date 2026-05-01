part of 'game_bloc.dart';

@freezed
sealed class GameEvent with _$GameEvent {
  const factory GameEvent.initialEvent() = InitialEvent;

  const factory GameEvent.rollDice() = RollDiceEvent;

  const factory GameEvent.diceRolled({required final int diceValue}) =
      DiceRolledEvent;

  const factory GameEvent.ballRolled({required final int diceValue}) =
      BallRolledEvent;

  const factory GameEvent.selectToken({required final String id}) =
      SelectTokenEvent;

  const factory GameEvent.moveTo({required final int c, required final int r}) =
      MoveToEvent;

  const factory GameEvent.nextTurn() = NextTurnEvent;

  const factory GameEvent.tick() = TickEvent;

  const factory GameEvent.resetGame() = ResetGameEvent;

  const factory GameEvent.goalFlashClear() = GoalFlashClearEvent;

  const factory GameEvent.coinTossComplete({required final Team winner}) =
      CoinTossCompleteEvent;

  const factory GameEvent.refreshSettings() = RefreshSettingsEvent;
}

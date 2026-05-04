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

  /// Online-1v1: full state push from the wire. Dispatched by
  /// [OnlineGameController] every time the `matches/{id}` doc changes
  /// AND the change wasn't initiated by us (filter via
  /// `last_move_by_uid`). The handler replaces the local state
  /// wholesale with the doc's contents.
  ///
  /// IMPORTANT: this is the ONLY event in the bloc that does NOT
  /// trigger a Firestore push back via `onTransition`. That filter
  /// is what prevents a sync loop between the two clients.
  const factory GameEvent.applyRemoteState({
    required final OnlineMatch match,
    required final OnlineContext context,
  }) = ApplyRemoteStateEvent;

  /// Online-1v1: install (or clear) the local online context. Called
  /// once by [OnlineGameController.start] before the first remote
  /// sync, and once on dispose to clear it. Keeping this separate
  /// from [ApplyRemoteStateEvent] means we can attach the context
  /// without tearing down the rest of the bloc state — useful on
  /// re-entries (e.g. rematch).
  const factory GameEvent.attachOnlineContext({
    required final OnlineContext? context,
  }) = AttachOnlineContextEvent;
}

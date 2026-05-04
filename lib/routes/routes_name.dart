class RouteName {
  RouteName._();

  static const String splashScreen = '/';
  static const String homeScreen = '/home';
  static const String gameScreen = '/game';
  static const String settingsScreen = '/settings';
  static const String guideScreen = '/guide';

  // ── Online 1v1 (Pass 2) ─────────────────────────────────────────
  /// Hub screen with three options: random match, create room, join
  /// room. Pushed when the user taps "PLAY ONLINE" on the home screen.
  static const String onlineLobbyScreen = '/online/lobby';

  /// "Looking for opponent…" screen. Pushed after the user hits
  /// FIND MATCH from the lobby. Pops itself with the new match id
  /// once a pair-up succeeds, or with `null` if the user cancels.
  static const String onlineMatchmakingScreen = '/online/matchmaking';

  /// Host-side: shows the freshly-generated 4-letter share code and
  /// waits for the opponent to join. Pops with the match id when the
  /// joiner stamps it on the room doc.
  static const String onlineRoomCreateScreen = '/online/room/create';

  /// Joiner-side: 4-letter code input. Pops with the match id on a
  /// successful join, or `null` if cancelled.
  static const String onlineRoomJoinScreen = '/online/room/join';
}

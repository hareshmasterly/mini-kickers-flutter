enum Team { red, blue }

enum GamePhase { coinToss, roll, move, moveBall, gameOver }

/// How the current match is being played.
///
/// `vsHuman` — local pass-and-play; both teams are controlled by humans
/// sharing the device. This is the default.
///
/// `vsAi` — single-player; the human plays as Red and the AI plays as
/// Blue. The mode is **not persisted across app launches**: every match
/// is started fresh from the home screen, so the user picks their mode
/// each time. AI difficulty (which IS persisted) lives in
/// [SettingsService.aiDifficulty].
///
/// `vsOnline` — Internet 1v1 against another anonymous-Auth user. The
/// local bloc still owns the gameplay loop, but moves are mirrored
/// through Firestore via `MatchService` so both clients see the same
/// state. The user picks their team (red / blue) at match-create time
/// based on the coin toss recorded in the `matches/{id}` doc.
enum GameMode { vsHuman, vsAi, vsOnline }

/// AI tuning tier. The user picks this from the difficulty dialog when
/// starting a VS AI match (or from Settings). Each tier maps to a set
/// of scoring + randomness + delay knobs that ultimately come from the
/// remote `app_settings.ai_settings` document — see
/// [SettingsService.aiRandomFactor] / [aiThinkDelayMs] / [aiUseLookahead].
enum AiDifficulty { easy, medium, hard }

extension AiDifficultyX on AiDifficulty {
  /// Stable string id used for SharedPreferences and the Firestore
  /// `ai_default_difficulty` field.
  String get id {
    switch (this) {
      case AiDifficulty.easy:
        return 'easy';
      case AiDifficulty.medium:
        return 'medium';
      case AiDifficulty.hard:
        return 'hard';
    }
  }

  static AiDifficulty? fromId(final String? raw) {
    switch (raw) {
      case 'easy':
        return AiDifficulty.easy;
      case 'medium':
        return AiDifficulty.medium;
      case 'hard':
        return AiDifficulty.hard;
      default:
        return null;
    }
  }
}

class Pos {
  final int c;
  final int r;
  const Pos(this.c, this.r);

  @override
  bool operator ==(final Object other) =>
      other is Pos && other.c == c && other.r == r;

  @override
  int get hashCode => Object.hash(c, r);
}

class Token {
  final String id;
  final Team team;
  final int c;
  final int r;

  const Token({
    required this.id,
    required this.team,
    required this.c,
    required this.r,
  });

  Token copyWith({final int? c, final int? r}) =>
      Token(id: id, team: team, c: c ?? this.c, r: r ?? this.r);
}

class GameConfig {
  static const int cols = 11;
  static const int rows = 7;
  static const int matchSeconds = 900;
  static const Pos initialBall = Pos(5, 3);

  static List<Token> initialTokens() => const <Token>[
        Token(id: 'r0', team: Team.red, c: 1, r: 2),
        Token(id: 'r1', team: Team.red, c: 1, r: 3),
        Token(id: 'r2', team: Team.red, c: 2, r: 4),
        Token(id: 'b0', team: Team.blue, c: 9, r: 2),
        Token(id: 'b1', team: Team.blue, c: 9, r: 3),
        Token(id: 'b2', team: Team.blue, c: 8, r: 4),
      ];

  static bool isGoalCell(final int c, final int r) =>
      (c == 0 || c == cols - 1) && r >= 2 && r <= 4;
}

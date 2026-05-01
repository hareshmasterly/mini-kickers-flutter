enum Team { red, blue }

enum GamePhase { coinToss, roll, move, moveBall, gameOver }

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

import 'package:mini_kickers/data/models/game_models.dart';

class GameLogic {
  GameLogic._();

  /// [ball] is the current ball position. It's used as an exception to the
  /// "tokens cannot enter goal columns" rule: a token IS allowed to land on
  /// the ball's cell even if that cell is in column 0 or column 10. Without
  /// this exception, a ball that ends up in a goal column outside the net
  /// rows (e.g. col 0 row 1) gets permanently stuck — no token could ever
  /// reach it to kick it back into play. Pass `null` only from contexts
  /// where the ball position is unknown; new code should always pass it.
  static List<Pos> getReachable({
    required final List<Token> tokens,
    required final Team turn,
    required final int sc,
    required final int sr,
    required final int steps,
    required final bool isBall,
    final Pos? ball,
  }) {
    final Set<Pos> results = <Pos>{};
    final Set<Pos> visited = <Pos>{Pos(sc, sr)};

    bool occupied(final int c, final int r) {
      for (final Token t in tokens) {
        if (t.c == c && t.r == r) return true;
      }
      return false;
    }

    bool isBallCell(final int c, final int r) =>
        ball != null && ball.c == c && ball.r == r;

    void dfs(final int c, final int r, final int rem) {
      if (rem == 0) {
        if (occupied(c, r)) return;

        if (!isBall) {
          if (GameConfig.isGoalCell(c, r)) return;
          // Tokens are normally blocked from goal columns 0 and 10, BUT a
          // token is allowed to land on the ball's cell even there — that's
          // how a ball stuck in a goal column (outside net rows) gets back
          // into play. Without this exception the game can deadlock.
          if ((c == 0 || c == GameConfig.cols - 1) && !isBallCell(c, r)) {
            return;
          }
        }

        if (isBall && r >= 2 && r <= 4) {
          if (turn == Team.red && c == 0) return;
          if (turn == Team.blue && c == GameConfig.cols - 1) return;
        }

        results.add(Pos(c, r));
        return;
      }

      const List<List<int>> dirs = <List<int>>[
        <int>[1, 0],
        <int>[-1, 0],
        <int>[0, 1],
        <int>[0, -1],
      ];

      for (final List<int> d in dirs) {
        final int nc = c + d[0];
        final int nr = r + d[1];
        if (nc < 0 || nc >= GameConfig.cols) continue;
        if (nr < 0 || nr >= GameConfig.rows) continue;
        final Pos p = Pos(nc, nr);
        if (visited.contains(p)) continue;
        visited.add(p);
        dfs(nc, nr, rem - 1);
        visited.remove(p);
      }
    }

    dfs(sc, sr, steps);
    return results.toList();
  }

  static bool teamHasAnyMove({
    required final List<Token> tokens,
    required final Team turn,
    required final int dice,
    final Pos? ball,
  }) {
    for (final Token t in tokens) {
      if (t.team != turn) continue;
      final List<Pos> reach = getReachable(
        tokens: tokens,
        turn: turn,
        sc: t.c,
        sr: t.r,
        steps: dice,
        isBall: false,
        ball: ball,
      );
      if (reach.isNotEmpty) return true;
    }
    return false;
  }

  static bool isGoalScored({required final Pos ball, required final Team turn}) {
    if (turn == Team.red &&
        ball.c == GameConfig.cols - 1 &&
        ball.r >= 2 &&
        ball.r <= 4) {
      return true;
    }
    if (turn == Team.blue && ball.c == 0 && ball.r >= 2 && ball.r <= 4) {
      return true;
    }
    return false;
  }
}

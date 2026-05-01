import 'package:mini_kickers/data/models/game_models.dart';

class GameLogic {
  GameLogic._();

  static List<Pos> getReachable({
    required final List<Token> tokens,
    required final Team turn,
    required final int sc,
    required final int sr,
    required final int steps,
    required final bool isBall,
  }) {
    final Set<Pos> results = <Pos>{};
    final Set<Pos> visited = <Pos>{Pos(sc, sr)};

    bool occupied(final int c, final int r) {
      for (final Token t in tokens) {
        if (t.c == c && t.r == r) return true;
      }
      return false;
    }

    void dfs(final int c, final int r, final int rem) {
      if (rem == 0) {
        if (occupied(c, r)) return;

        if (!isBall) {
          if (GameConfig.isGoalCell(c, r)) return;
          if (c == 0 || c == GameConfig.cols - 1) return;
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

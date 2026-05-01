import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/team_colors.dart';
import 'package:mini_kickers/views/game/widget/animated_highlight.dart';
import 'package:mini_kickers/views/game/widget/animated_token.dart';
import 'package:mini_kickers/views/game/widget/ball_3d.dart';

class BoardWidget extends StatelessWidget {
  const BoardWidget({super.key});

  @override
  Widget build(final BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (final BuildContext context, final Widget? child) =>
          BlocBuilder<GameBloc, GameState>(
        builder: (final BuildContext context, final GameState state) {
        return LayoutBuilder(
          builder: (final BuildContext ctx, final BoxConstraints cons) {
            final double cellW = cons.maxWidth / GameConfig.cols;
            final double cellH = cons.maxHeight / GameConfig.rows;
            final double cell = cellW < cellH ? cellW : cellH;
            final double boardW = cell * GameConfig.cols;
            final double boardH = cell * GameConfig.rows;

            return Center(
              child: Container(
                width: boardW,
                height: boardH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                    width: 3,
                  ),
                  boxShadow: <BoxShadow>[
                    const BoxShadow(
                      color: AppColors.greenMid,
                      spreadRadius: 6,
                    ),
                    BoxShadow(
                      color: TeamColors.primary(state.turn)
                          .withValues(alpha: 0.3),
                      blurRadius: 32,
                      spreadRadius: 1,
                    ),
                    const BoxShadow(
                      color: Colors.black87,
                      blurRadius: 60,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    children: <Widget>[
                      _PitchLayer(cell: cell),
                      const _CrowdGlowLayer(),
                      ..._buildHighlights(context, state, cell),
                      ..._buildTokens(context, state, cell),
                      Ball3D(ball: state.ball, cell: cell),
                      // CommentaryToast moved out of the board to the
                      // screen-level Stack in GameScreen — it now lives
                      // at the top-right corner of the screen so it
                      // never overlaps the pitch / tokens / ball.
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      ),
    );
  }

  List<Widget> _buildHighlights(
    final BuildContext context,
    final GameState state,
    final double cell,
  ) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < state.highlights.length; i++) {
      final Pos p = state.highlights[i];
      out.add(
        Positioned(
          left: p.c * cell,
          top: p.r * cell,
          width: cell,
          height: cell,
          child: AnimatedHighlight(
            indexDelay: i,
            onTap: () => context
                .read<GameBloc>()
                .add(GameEvent.moveTo(c: p.c, r: p.r)),
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _buildTokens(
    final BuildContext context,
    final GameState state,
    final double cell,
  ) {
    return state.tokens.map((final Token t) {
      final bool isSelected = state.selectedTokenId == t.id;
      final bool isSelectable = state.phase == GamePhase.move &&
          t.team == state.turn &&
          state.selectedTokenId == null;
      // True for every token of the team whose turn it is during the
      // pre-roll and pick-a-token phases. Surfaces a slow dashed ring
      // so the active side is obvious at a glance — including before
      // the dice has been rolled, where there used to be no on-board
      // cue at all.
      final bool isActiveTeam = t.team == state.turn &&
          (state.phase == GamePhase.roll ||
              state.phase == GamePhase.move);
      return AnimatedToken(
        key: ValueKey<String>(t.id),
        token: t,
        cell: cell,
        isSelected: isSelected,
        isSelectable: isSelectable,
        isActiveTeam: isActiveTeam,
        onTap: () =>
            context.read<GameBloc>().add(GameEvent.selectToken(id: t.id)),
      );
    }).toList();
  }
}

class _PitchLayer extends StatelessWidget {
  const _PitchLayer({required this.cell});
  final double cell;

  @override
  Widget build(final BuildContext context) {
    return CustomPaint(
      size: Size(cell * GameConfig.cols, cell * GameConfig.rows),
      painter: _PitchPainter(cell: cell),
    );
  }
}

class _CrowdGlowLayer extends StatefulWidget {
  const _CrowdGlowLayer();

  @override
  State<_CrowdGlowLayer> createState() => _CrowdGlowLayerState();
}

class _CrowdGlowLayerState extends State<_CrowdGlowLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (final BuildContext context, final Widget? child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _CrowdGlowPainter(t: _ctrl.value),
          );
        },
      ),
    );
  }
}

class _CrowdGlowPainter extends CustomPainter {
  _CrowdGlowPainter({required this.t});
  final double t;

  @override
  void paint(final Canvas canvas, final Size size) {
    final double sweepX = size.width * (t * 1.6 - 0.3);
    final Paint sweep = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromLTWH(sweepX - 80, 0, 160, size.height),
      );
    canvas.drawRect(
      Rect.fromLTWH(sweepX - 80, 0, 160, size.height),
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant final _CrowdGlowPainter old) => old.t != t;
}

class _PitchPainter extends CustomPainter {
  _PitchPainter({required this.cell});
  final double cell;

  @override
  void paint(final Canvas canvas, final Size size) {
    final Paint bg = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: <Color>[
          AppColors.greenLight,
          AppColors.green,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final Paint stripe = Paint()..color = Colors.white.withValues(alpha: 0.04);
    for (int i = 0; i < GameConfig.cols; i += 4) {
      canvas.drawRect(
        Rect.fromLTWH(i * cell, 0, cell * 2, size.height),
        stripe,
      );
    }

    final Paint line = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int c = 0; c <= GameConfig.cols; c++) {
      canvas.drawLine(
        Offset(c * cell, 0),
        Offset(c * cell, size.height),
        line,
      );
    }
    for (int r = 0; r <= GameConfig.rows; r++) {
      canvas.drawLine(
        Offset(0, r * cell),
        Offset(size.width, r * cell),
        line,
      );
    }

    final Paint halfway = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(5.5 * cell, 0), Offset(5.5 * cell, size.height), halfway);

    final Paint centerCircle = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(5.5 * cell, 3.5 * cell), cell * 0.8, centerCircle);
    final Paint centerSpot = Paint()..color = Colors.white.withValues(alpha: 0.7);
    canvas.drawCircle(Offset(5.5 * cell, 3.5 * cell), 3, centerSpot);

    final Paint goalGradient = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          Color(0xFF2C5230),
          AppColors.goalCell,
        ],
      ).createShader(
        const Rect.fromLTWH(0, 0, 1, 1),
      );
    final Paint netHatch = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final Paint goalBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;

    for (final int col in <int>[0, GameConfig.cols - 1]) {
      for (int r = 2; r <= 4; r++) {
        final Rect rect = Rect.fromLTWH(col * cell, r * cell, cell, cell);
        canvas.drawRect(rect, goalGradient);
        for (double y = rect.top; y < rect.bottom; y += 6) {
          canvas.drawLine(
            Offset(rect.left, y),
            Offset(rect.right, y),
            netHatch,
          );
        }
        for (double x = rect.left; x < rect.right; x += 6) {
          canvas.drawLine(
            Offset(x, rect.top),
            Offset(x, rect.bottom),
            netHatch,
          );
        }
      }
      canvas.drawLine(
        Offset(col * cell, 2 * cell),
        Offset((col + 1) * cell, 2 * cell),
        goalBorder,
      );
      canvas.drawLine(
        Offset(col * cell, 5 * cell),
        Offset((col + 1) * cell, 5 * cell),
        goalBorder,
      );
    }

    final Paint cornerArc = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final List<Offset> corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    for (final Offset corner in corners) {
      final double startAngle = (corner == Offset.zero)
          ? 0
          : (corner.dx > 0 && corner.dy == 0)
              ? pi / 2
              : (corner.dx == 0 && corner.dy > 0)
                  ? -pi / 2
                  : pi;
      canvas.drawArc(
        Rect.fromCircle(center: corner, radius: cell * 0.35),
        startAngle,
        pi / 2,
        false,
        cornerArc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant final _PitchPainter old) => old.cell != cell;
}

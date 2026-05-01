import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';

/// A bold gold-metallic ring that draws itself in clockwise as `progress`
/// goes 0 → 1, then continuously rotates. Rendered with simple
/// `canvas.drawArc` calls — no blur masks, no shaders.
class GoldRing extends StatelessWidget {
  const GoldRing({
    super.key,
    required this.progress,        // 0..1 reveal
    required this.spinProgress,    // 0..1 looping spin
    required this.diameter,
  });

  final double progress;
  final double spinProgress;
  final double diameter;

  @override
  Widget build(final BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _RingPainter(
          reveal: progress.clamp(0.0, 1.0),
          rotation: spinProgress * 2 * pi,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.reveal, required this.rotation});
  final double reveal;
  final double rotation;

  @override
  void paint(final Canvas canvas, final Size size) {
    if (reveal <= 0) return;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width / 2) - 6;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final double sweep = reveal * 2 * pi;

    // Outer thin gold rim
    final Paint outerStroke = Paint()
      ..shader = SweepGradient(
        colors: const <Color>[
          AppColors.goldDeep,
          AppColors.goldBright,
          AppColors.goldShine,
          AppColors.goldBright,
          AppColors.goldDeep,
        ],
        transform: GradientRotation(rotation),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2 + rotation, sweep, false, outerStroke);

    // Inner thinner accent line
    final Rect innerRect = Rect.fromCircle(center: center, radius: radius - 8);
    final Paint innerStroke = Paint()
      ..color = AppColors.goldShine.withValues(alpha: 0.8 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawArc(innerRect, -pi / 2 + rotation, sweep, false, innerStroke);

    // 4 anchor pegs at cardinal positions (only show as reveal passes them)
    for (int i = 0; i < 4; i++) {
      final double angle = -pi / 2 + i * (pi / 2) + rotation;
      // Show this peg only if the sweep has reached its position
      final double pegPhase = (i * 0.25);
      if (reveal < pegPhase) continue;
      final Offset peg = center +
          Offset(cos(angle), sin(angle)) * radius;
      final Paint pegPaint = Paint()
        ..color = AppColors.goldShine
        ..style = PaintingStyle.fill;
      canvas.drawCircle(peg, 4, pegPaint);
    }
  }

  @override
  bool shouldRepaint(covariant final _RingPainter old) =>
      old.reveal != reveal || old.rotation != rotation;
}

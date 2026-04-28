import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';

/// Climax effect: a radial shockwave ring expanding outward, plus a
/// fan of gold rays bursting from centre. Fires once during the title
/// reveal to mark the "kick-off" moment.
///
/// `progress` 0 → 1:
///   • 0.0–0.55  shockwave expands from 0 → maxRadius
///   • 0.0–1.0   rays grow then fade
///   • 0.55–1.0  ring opacity fades to 0
class GoalBurst extends StatelessWidget {
  const GoalBurst({
    super.key,
    required this.progress,
    required this.diameter,
  });

  final double progress;
  final double diameter;

  @override
  Widget build(final BuildContext context) {
    if (progress <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          painter: _BurstPainter(t: progress.clamp(0.0, 1.0)),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t});

  final double t;
  static const int _rayCount = 14;

  @override
  void paint(final Canvas canvas, final Size size) {
    final Offset centre = size.center(Offset.zero);
    final double maxR = size.width / 2;

    // ── Shockwave ring ─────────────────────────────────────────────────
    final double ringT = (t / 0.55).clamp(0.0, 1.0);
    final double ringEased = Curves.easeOutCubic.transform(ringT);
    final double ringRadius = ringEased * maxR * 1.05;
    final double ringFade = (1 - ((t - 0.35) / 0.65).clamp(0.0, 1.0));
    if (ringFade > 0 && ringRadius > 4) {
      final Paint ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + (1 - ringEased) * 4
        ..color = AppColors.goldShine.withValues(alpha: 0.85 * ringFade);
      canvas.drawCircle(centre, ringRadius, ring);

      // Trailing softer ring just inside.
      final Paint inner = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppColors.goldBright.withValues(alpha: 0.55 * ringFade);
      canvas.drawCircle(centre, ringRadius - 6, inner);
    }

    // ── Rays ───────────────────────────────────────────────────────────
    // Each ray grows outward then fades. Triangular profile: thin line.
    final double rayT = Curves.easeOutCubic.transform(
      (t / 0.7).clamp(0.0, 1.0),
    );
    final double rayFade =
        (1 - ((t - 0.55) / 0.45).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    if (rayFade <= 0 || rayT <= 0) {
      return;
    }
    final double inner = maxR * 0.32;
    final double outer = inner + (maxR * 0.85 - inner) * rayT;

    final Paint ray = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4
      ..color = AppColors.goldShine.withValues(alpha: 0.9 * rayFade);

    for (int i = 0; i < _rayCount; i++) {
      // Stagger angles so the burst feels organic, not like a clock.
      final double angle = (i / _rayCount) * 2 * pi + (i.isEven ? 0 : 0.18);
      final Offset start = centre + Offset(cos(angle), sin(angle)) * inner;
      final Offset end = centre + Offset(cos(angle), sin(angle)) * outer;
      canvas.drawLine(start, end, ray);
    }
  }

  @override
  bool shouldRepaint(covariant final _BurstPainter old) => old.t != t;
}

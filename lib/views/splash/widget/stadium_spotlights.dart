import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';

/// Four stadium spotlights converging from the corners onto the centre.
///
/// `progress` 0 → 1:
///   • 0.0–0.7  beams sweep inward from the corners and grow brighter
///   • 0.7–1.0  beams fade out, leaving the hero to take over
///
/// Cheap to render: four `Path`-based gradient cones drawn with simple
/// `LinearGradient` shaders. No blur, no `BackdropFilter`.
class StadiumSpotlights extends StatelessWidget {
  const StadiumSpotlights({super.key, required this.progress});

  final double progress;

  @override
  Widget build(final BuildContext context) {
    if (progress <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SpotlightsPainter(progress: progress.clamp(0.0, 1.0)),
      ),
    );
  }
}

class _SpotlightsPainter extends CustomPainter {
  _SpotlightsPainter({required this.progress});

  final double progress;

  @override
  void paint(final Canvas canvas, final Size size) {
    // Two-stage envelope: ramp to peak by 0.7, then ease out by 1.0.
    final double rampIn = Curves.easeOutCubic.transform(
      (progress / 0.7).clamp(0.0, 1.0),
    );
    final double rampOut = Curves.easeInCubic.transform(
      ((progress - 0.7) / 0.3).clamp(0.0, 1.0),
    );
    final double intensity = (rampIn * (1 - rampOut)).clamp(0.0, 1.0);
    if (intensity <= 0) return;

    final Offset centre = size.center(Offset.zero);
    final double diag = sqrt(size.width * size.width + size.height * size.height);

    // Each beam: anchor (origin corner), aim (centre), half-width that
    // narrows at the source and widens at the target.
    final List<Offset> corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];

    for (final Offset corner in corners) {
      final Offset dir = (centre - corner) / diag;
      // Perpendicular for spreading the cone.
      final Offset perp = Offset(-dir.dy, dir.dx);

      // The beam sweeps inward — start short, grow to full diag length.
      final double length = diag * (0.55 + 0.45 * rampIn);
      final Offset tip = corner + dir * length;

      final double sourceHalfWidth = 8;
      final double tipHalfWidth = size.shortestSide * 0.42;

      final Path path = Path()
        ..moveTo(
          corner.dx + perp.dx * sourceHalfWidth,
          corner.dy + perp.dy * sourceHalfWidth,
        )
        ..lineTo(
          corner.dx - perp.dx * sourceHalfWidth,
          corner.dy - perp.dy * sourceHalfWidth,
        )
        ..lineTo(
          tip.dx - perp.dx * tipHalfWidth,
          tip.dy - perp.dy * tipHalfWidth,
        )
        ..lineTo(
          tip.dx + perp.dx * tipHalfWidth,
          tip.dy + perp.dy * tipHalfWidth,
        )
        ..close();

      final Paint beam = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.goldShine.withValues(alpha: 0.0),
            AppColors.goldShine.withValues(alpha: 0.18 * intensity),
            AppColors.goldBright.withValues(alpha: 0.05 * intensity),
            AppColors.goldShine.withValues(alpha: 0.0),
          ],
          stops: const <double>[0.0, 0.35, 0.7, 1.0],
        ).createShader(Rect.fromPoints(corner, tip));

      canvas.drawPath(path, beam);
    }

    // Faint warm wash over the centre where the beams converge.
    final Paint hotspot = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.goldShine.withValues(alpha: 0.22 * intensity),
          AppColors.goldBright.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: centre, radius: size.shortestSide * 0.4),
      );
    canvas.drawCircle(centre, size.shortestSide * 0.4, hotspot);
  }

  @override
  bool shouldRepaint(covariant final _SpotlightsPainter old) =>
      old.progress != progress;
}

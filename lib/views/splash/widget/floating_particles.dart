import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';

/// Subtle gold dust particles drifting upward. Pre-computed positions, one
/// CustomPainter — extremely cheap (~30 small `drawCircle` calls per frame).
class FloatingParticles extends StatelessWidget {
  const FloatingParticles({super.key, required this.t});
  final double t; // looping 0..1

  static final List<_Particle> _seeds = _makeSeeds();

  static List<_Particle> _makeSeeds() {
    final Random rng = Random(73);
    return List<_Particle>.generate(
      28,
      (final int i) => _Particle(
        x: rng.nextDouble(),
        y0: rng.nextDouble(),
        speed: 0.25 + rng.nextDouble() * 0.55,
        size: 1.2 + rng.nextDouble() * 2.4,
        phase: rng.nextDouble(),
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _Painter(particles: _seeds, t: t),
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y0,
    required this.speed,
    required this.size,
    required this.phase,
  });
  final double x;
  final double y0;
  final double speed;
  final double size;
  final double phase;
}

class _Painter extends CustomPainter {
  _Painter({required this.particles, required this.t});
  final List<_Particle> particles;
  final double t;

  @override
  void paint(final Canvas canvas, final Size size) {
    final Paint dot = Paint()..color = AppColors.goldShine;
    for (final _Particle p in particles) {
      final double progress = (t * p.speed + p.phase) % 1.0;
      final double y = size.height * (1 - progress);
      final double drift = sin(progress * pi * 4 + p.phase * pi * 2) * 14;
      final double x = size.width * p.x + drift;
      final double opacity = sin(progress * pi).clamp(0.0, 1.0) * 0.55;
      dot.color = AppColors.goldShine.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), p.size, dot);
    }
  }

  @override
  bool shouldRepaint(covariant final _Painter old) => old.t != t;
}

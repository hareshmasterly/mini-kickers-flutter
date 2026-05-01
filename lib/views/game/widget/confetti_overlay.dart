import 'dart:math';

import 'package:flutter/material.dart';

class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, required this.particleCount});
  final int particleCount;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    final Random rng = Random();
    _particles = List<_Particle>.generate(
      widget.particleCount,
      (final int i) => _Particle.random(rng),
    );
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
            painter: _ConfettiPainter(
              particles: _particles,
              t: _ctrl.value,
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.startX,
    required this.startY,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.rotation,
    required this.spin,
    required this.shape,
  });

  factory _Particle.random(final Random rng) {
    final List<Color> palette = <Color>[
      const Color(0xFFE53935),
      const Color(0xFF1E88E5),
      const Color(0xFFFFC107),
      const Color(0xFF43A047),
      const Color(0xFFAB47BC),
      const Color(0xFFFFFFFF),
    ];
    return _Particle(
      startX: rng.nextDouble(),
      startY: 0.45 + rng.nextDouble() * 0.1,
      vx: (rng.nextDouble() - 0.5) * 1.4,
      vy: -1.0 - rng.nextDouble() * 1.4,
      color: palette[rng.nextInt(palette.length)],
      size: 5 + rng.nextDouble() * 7,
      rotation: rng.nextDouble() * pi * 2,
      spin: (rng.nextDouble() - 0.5) * 12,
      shape: rng.nextInt(3),
    );
  }

  final double startX;
  final double startY;
  final double vx;
  final double vy;
  final Color color;
  final double size;
  final double rotation;
  final double spin;
  final int shape;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.t});
  final List<_Particle> particles;
  final double t;

  @override
  void paint(final Canvas canvas, final Size size) {
    final double gravity = 1.6;
    for (final _Particle p in particles) {
      final double cx = size.width * p.startX + p.vx * size.width * t;
      final double cy = size.height * p.startY +
          p.vy * size.height * t +
          gravity * size.height * t * t;
      final double opacity = (1 - t * 1.05).clamp(0.0, 1.0);
      final Paint paint = Paint()
        ..color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(p.rotation + p.spin * t);
      switch (p.shape) {
        case 0:
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.45,
            ),
            paint,
          );
          break;
        case 1:
          canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
          break;
        default:
          final Path tri = Path()
            ..moveTo(0, -p.size * 0.5)
            ..lineTo(p.size * 0.5, p.size * 0.4)
            ..lineTo(-p.size * 0.5, p.size * 0.4)
            ..close();
          canvas.drawPath(tri, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant final _ConfettiPainter old) => old.t != t;
}

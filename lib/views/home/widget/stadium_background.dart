import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';

class StadiumBackground extends StatefulWidget {
  const StadiumBackground({super.key});

  @override
  State<StadiumBackground> createState() => _StadiumBackgroundState();
}

class _StadiumBackgroundState extends State<StadiumBackground>
    with TickerProviderStateMixin {
  late final AnimationController _spotlight;
  late final AnimationController _particles;
  late final List<_Particle> _particleList;

  @override
  void initState() {
    super.initState();
    _spotlight = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _particles = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    final Random rng = Random(42);
    _particleList = List<_Particle>.generate(
      36,
      (final int i) => _Particle.random(rng),
    );
  }

  @override
  void dispose() {
    _spotlight.dispose();
    _particles.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const _BaseGradient(),
        AnimatedBuilder(
          animation: _spotlight,
          builder: (final BuildContext context, final Widget? child) {
            return CustomPaint(
              painter: _SpotlightPainter(t: _spotlight.value),
              size: Size.infinite,
            );
          },
        ),
        AnimatedBuilder(
          animation: _particles,
          builder: (final BuildContext context, final Widget? child) {
            return CustomPaint(
              painter: _ParticlePainter(
                particles: _particleList,
                t: _particles.value,
              ),
              size: Size.infinite,
            );
          },
        ),
        const _Vignette(),
      ],
    );
  }
}

class _BaseGradient extends StatelessWidget {
  const _BaseGradient();

  @override
  Widget build(final BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.stadiumMid,
            AppColors.stadiumDeep,
            Color(0xFF000000),
          ],
          stops: <double>[0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(final BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: <Color>[
              Color(0x00000000),
              Color(0x66000000),
              Color(0xCC000000),
            ],
            stops: <double>[0.55, 0.85, 1.0],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.t});
  final double t;

  @override
  void paint(final Canvas canvas, final Size size) {
    _drawBeam(
      canvas,
      size,
      origin: Offset(size.width * 0.15, -40),
      angle: pi / 3 + sin(t * pi * 2) * 0.18,
      length: size.height * 1.4,
      width: size.width * 0.55,
      color: AppColors.limeBright.withValues(alpha: 0.06),
    );
    _drawBeam(
      canvas,
      size,
      origin: Offset(size.width * 0.85, -40),
      angle: 2 * pi / 3 - cos(t * pi * 2) * 0.18,
      length: size.height * 1.4,
      width: size.width * 0.5,
      color: AppColors.goldBright.withValues(alpha: 0.05),
    );
    _drawBeam(
      canvas,
      size,
      origin: Offset(size.width * 0.5, -40),
      angle: pi / 2 + sin(t * pi * 2 + pi) * 0.12,
      length: size.height * 1.5,
      width: size.width * 0.45,
      color: Colors.white.withValues(alpha: 0.04),
    );
  }

  void _drawBeam(
    final Canvas canvas,
    final Size size, {
    required final Offset origin,
    required final double angle,
    required final double length,
    required final double width,
    required final Color color,
  }) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle - pi / 2);
    final Path path = Path()
      ..moveTo(-12, 0)
      ..lineTo(12, 0)
      ..lineTo(width / 2, length)
      ..lineTo(-width / 2, length)
      ..close();
    final Paint paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(-width / 2, 0, width, length))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant final _SpotlightPainter old) => old.t != t;
}

class _Particle {
  _Particle({
    required this.x,
    required this.startY,
    required this.size,
    required this.speed,
    required this.phase,
  });

  factory _Particle.random(final Random rng) => _Particle(
        x: rng.nextDouble(),
        startY: rng.nextDouble(),
        size: 1.0 + rng.nextDouble() * 2.5,
        speed: 0.3 + rng.nextDouble() * 0.6,
        phase: rng.nextDouble(),
      );

  final double x;
  final double startY;
  final double size;
  final double speed;
  final double phase;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles, required this.t});
  final List<_Particle> particles;
  final double t;

  @override
  void paint(final Canvas canvas, final Size size) {
    for (final _Particle p in particles) {
      final double progress = ((t * p.speed + p.phase) % 1.0);
      final double y = size.height * (1 - progress);
      final double drift = sin(progress * pi * 4 + p.phase * pi * 2) * 14;
      final double x = size.width * p.x + drift;
      final double opacity = (sin(progress * pi) * 0.6).clamp(0.0, 1.0);

      final Paint paint = Paint()
        ..color = AppColors.goldShine.withValues(alpha: opacity * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant final _ParticlePainter old) => old.t != t;
}

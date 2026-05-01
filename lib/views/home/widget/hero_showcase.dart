import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/views/game/widget/dice_3d_cube.dart';

class HeroShowcase extends StatefulWidget {
  const HeroShowcase({super.key, required this.diceSize});
  final double diceSize;

  @override
  State<HeroShowcase> createState() => _HeroShowcaseState();
}

class _HeroShowcaseState extends State<HeroShowcase>
    with TickerProviderStateMixin {
  late final AnimationController _halo;
  late final AnimationController _ballSpin;
  late final AnimationController _ballFloat;

  @override
  void initState() {
    super.initState();
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _ballSpin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _ballFloat = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _halo.dispose();
    _ballSpin.dispose();
    _ballFloat.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final double ballSize = widget.diceSize * 0.7;
    final double containerSize = widget.diceSize * 2.4;

    return SizedBox(
      width: containerSize,
      height: containerSize * 0.85,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _halo,
            builder: (final BuildContext context, final Widget? child) {
              final double t = _halo.value;
              final double scale = 0.85 + t * 0.35;
              final double opacity = 0.18 + t * 0.22;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: containerSize * 0.9,
                  height: containerSize * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        AppColors.goldBright.withValues(alpha: opacity),
                        AppColors.goldDeep.withValues(alpha: opacity * 0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          CustomPaint(
            size: Size(containerSize * 0.7, 18),
            painter: _GroundShadowPainter(),
          ).positionedOnGround(containerSize),
          AnimatedBuilder(
            animation: _ballFloat,
            builder: (final BuildContext context, final Widget? child) {
              final double float = sin(_ballFloat.value * pi) * 14;
              return Transform.translate(
                offset: Offset(containerSize * 0.34, -containerSize * 0.05 + float),
                child: child,
              );
            },
            child: AnimatedBuilder(
              animation: _ballSpin,
              builder: (final BuildContext context, final Widget? child) {
                return Transform.rotate(
                  angle: _ballSpin.value * pi * 2,
                  child: child,
                );
              },
              child: SizedBox(
                width: ballSize,
                height: ballSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: ballSize,
                      height: ballSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 18,
                            offset: const Offset(2, 8),
                          ),
                        ],
                      ),
                    ),
                    Image.asset(
                      'assets/images/football.png',
                      width: ballSize,
                      height: ballSize,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _ballFloat,
            builder: (final BuildContext context, final Widget? child) {
              final double bob = sin(_ballFloat.value * pi + pi / 2) * 8;
              return Transform.translate(
                offset: Offset(0, bob),
                child: child,
              );
            },
            child: Dice3DCube(
              value: 5,
              isRolling: true,
              glowColor: AppColors.goldBright,
              size: widget.diceSize,
            ),
          ),
        ],
      ),
    );
  }
}

extension on Widget {
  Widget positionedOnGround(final double containerSize) {
    return Positioned(
      bottom: containerSize * 0.05,
      child: this,
    );
  }
}

class _GroundShadowPainter extends CustomPainter {
  @override
  void paint(final Canvas canvas, final Size size) {
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.black.withValues(alpha: 0.55),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant final CustomPainter old) => false;
}


import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/game_models.dart';

class Ball3D extends StatefulWidget {
  const Ball3D({super.key, required this.ball, required this.cell});
  final Pos ball;
  final double cell;

  @override
  State<Ball3D> createState() => _Ball3DState();
}

class _Ball3DState extends State<Ball3D> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _arrival;
  static const Duration _idleSpin = Duration(seconds: 5);
  static const Duration _kickSpin = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: _idleSpin)..repeat();
    _arrival = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didUpdateWidget(covariant final Ball3D old) {
    super.didUpdateWidget(old);
    if (old.ball != widget.ball) {
      _arrival
        ..reset()
        ..forward();
      _spin.duration = _kickSpin;
      _spin
        ..reset()
        ..forward().whenComplete(() {
          _spin.duration = _idleSpin;
          _spin.repeat();
        });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final double size = widget.cell * 0.62;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      left: widget.ball.c * widget.cell + (widget.cell - size) / 2,
      top: widget.ball.r * widget.cell + (widget.cell - size) / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_spin, _arrival]),
          builder: (final BuildContext context, final Widget? child) {
            final double a = _arrival.value;
            final double bob = a > 0 ? 1.0 + sin(a * pi) * 0.22 : 1.0;
            return Transform.scale(
              scale: bob,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Transform.translate(
                    offset: Offset(2, size * 0.06),
                    child: Container(
                      width: size * 0.9,
                      height: size * 0.18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(size),
                        gradient: RadialGradient(
                          colors: <Color>[
                            Colors.black.withValues(alpha: 0.55),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Transform.rotate(
                    angle: _spin.value * pi * 2,
                    child: Image.asset(
                      'assets/images/football.png',
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

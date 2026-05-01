import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/views/game/widget/confetti_overlay.dart';

class GoalFlashWidget extends StatefulWidget {
  const GoalFlashWidget({super.key});

  @override
  State<GoalFlashWidget> createState() => _GoalFlashWidgetState();
}

class _GoalFlashWidgetState extends State<GoalFlashWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (final BuildContext context, final Widget? child) {
        final double t = _ctrl.value;
        final double flash = (1 - (t * 3).clamp(0.0, 1.0));
        final double scale = Curves.elasticOut.transform(t.clamp(0.0, 1.0));
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Container(color: Colors.black.withValues(alpha: 0.55 * (1 - t * 0.4))),
            if (flash > 0)
              Container(color: Colors.white.withValues(alpha: flash)),
            const ConfettiOverlay(particleCount: 80),
            Center(
              child: Transform.scale(
                scale: 0.4 + scale * 0.7,
                child: Transform.rotate(
                  angle: sin(t * pi * 4) * 0.05,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 50,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Color(0xFF111111),
                          Color(0xFF222222),
                        ],
                      ),
                      border: Border.all(color: Colors.yellow, width: 5),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.7),
                          blurRadius: 80,
                          spreadRadius: 8,
                        ),
                        const BoxShadow(
                          color: Colors.yellow,
                          blurRadius: 30,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      'GOAL!  ⚽',
                      style: AppFonts.bebasNeue(
                        fontSize: 90,
                        letterSpacing: 8,
                        color: AppColors.accent,
                        shadows: <Shadow>[
                          const Shadow(
                            color: Colors.yellow,
                            blurRadius: 28,
                          ),
                          Shadow(
                            color: AppColors.accent.withValues(alpha: 0.9),
                            blurRadius: 60,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

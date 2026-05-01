import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/theme/app_colors.dart';

class AnimatedScoreBox extends StatefulWidget {
  const AnimatedScoreBox({
    super.key,
    required this.label,
    required this.score,
    required this.borderColor,
    required this.textColor,
    this.compact = false,
  });

  final String label;
  final int score;
  final Color borderColor;
  final Color textColor;

  /// Tighter paddings + smaller score digits for mobile-landscape.
  final bool compact;

  @override
  State<AnimatedScoreBox> createState() => _AnimatedScoreBoxState();
}

class _AnimatedScoreBoxState extends State<AnimatedScoreBox>
    with TickerProviderStateMixin {
  late final AnimationController _flip;
  late final AnimationController _flash;
  late final AnimationController _floatUp;
  int _displayedScore = 0;

  @override
  void initState() {
    super.initState();
    _displayedScore = widget.score;
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _floatUp = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didUpdateWidget(covariant final AnimatedScoreBox old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      _flash
        ..reset()
        ..forward();
      _floatUp
        ..reset()
        ..forward();
      _flip
        ..reset()
        ..forward().whenComplete(() {
          if (!mounted) return;
          setState(() => _displayedScore = widget.score);
        });
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _flash.dispose();
    _floatUp.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_flip, _flash, _floatUp]),
      builder: (final BuildContext context, final Widget? child) {
        final double flashV = _flash.value;
        final double flashStrength = sin(flashV * pi);
        final double flipT = _flip.value;
        final double flipAngle = flipT * pi;

        final double labelSize = widget.compact ? 9 : 10;
        final double scoreSize = widget.compact ? 28 : 40;
        final EdgeInsets boxPad = widget.compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const EdgeInsets.all(10);
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              width: .maxFinite,
              padding: boxPad,
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                border: Border.all(
                  color: Color.lerp(
                    widget.borderColor.withValues(alpha: 0.45),
                    widget.borderColor,
                    flashStrength,
                  )!,
                  width: 1 + flashStrength * 2,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: widget.borderColor.withValues(alpha: 0.6 * flashStrength),
                    blurRadius: 18 * flashStrength,
                    spreadRadius: 2 * flashStrength,
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: labelSize,
                      color: widget.textColor,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: widget.compact ? 2 : 4),
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.002)
                      ..rotateX(flipAngle),
                    child: Text(
                      '${flipT < 0.5 ? _displayedScore : widget.score}',
                      style: AppFonts.bebasNeue(
                        fontSize: scoreSize,
                        color: widget.textColor,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_floatUp.isAnimating || _floatUp.value > 0)
              Positioned(
                top: -20 - 30 * Curves.easeOut.transform(_floatUp.value),
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: (1 - _floatUp.value).clamp(0.0, 1.0),
                    child: Text(
                      '+1',
                      style: AppFonts.bebasNeue(
                        fontSize: 28,
                        color: widget.textColor,
                        shadows: <Shadow>[
                          Shadow(
                            color: widget.textColor.withValues(alpha: 0.7),
                            blurRadius: 18,
                          ),
                        ],
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

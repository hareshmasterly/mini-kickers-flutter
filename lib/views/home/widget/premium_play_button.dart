import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';

class PremiumPlayButton extends StatefulWidget {
  const PremiumPlayButton({
    super.key,
    required this.onPressed,
    this.width = 320,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final double width;

  /// When `true`, renders a tighter pill (~52 dp tall, smaller font/icon)
  /// so the home screen fits without scrolling on short landscape
  /// phones. Off → original hero size for tablets and tall phones.
  final bool compact;

  @override
  State<PremiumPlayButton> createState() => _PremiumPlayButtonState();
}

class _PremiumPlayButtonState extends State<PremiumPlayButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _shine;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _shine.dispose();
    super.dispose();
  }

  void _handleTap() {
    AudioHelper.select();
    widget.onPressed();
  }

  @override
  Widget build(final BuildContext context) {
    // Compact = mobile landscape only. Regular = the original tablet/iPad
    // hero size — the user explicitly wants tablets to look full-size.
    final double height = widget.compact ? 44 : 76;
    final double fontSize = widget.compact ? 18 : 36;
    final double iconBoxSize = widget.compact ? 24 : 36;
    final double iconSize = widget.compact ? 16 : 24;
    final double iconGap = widget.compact ? 8 : 14;
    final double letterSpacing = widget.compact ? 3 : 6;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_pulse, _shine]),
      builder: (final BuildContext context, final Widget? child) {
        final double t = _pulse.value;
        final double shineT = _shine.value;
        final double glow = 22 + t * 36;
        final double spread = 2 + t * 6;
        return AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: GestureDetector(
            onTapDown: (final _) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (final _) {
              setState(() => _pressed = false);
              _handleTap();
            },
            child: Container(
              width: widget.width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height / 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.goldBright.withValues(alpha: 0.85),
                    blurRadius: glow,
                    spreadRadius: spread,
                  ),
                  BoxShadow(
                    color: AppColors.limeBright.withValues(alpha: 0.45),
                    blurRadius: glow * 0.7,
                    spreadRadius: spread * 0.6,
                  ),
                  const BoxShadow(
                    color: Colors.black54,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          AppColors.goldBright,
                          Color(0xFFFFA000),
                          Color(0xFFFF6F00),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(height / 2),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(height / 2),
                      child: Transform.translate(
                        offset: Offset(widget.width * (shineT * 1.6 - 0.5), 0),
                        child: Transform.rotate(
                          angle: -0.3,
                          child: Container(
                            width: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: <Color>[
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: 0.5),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: iconBoxSize,
                            height: iconBoxSize,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: iconSize,
                              color: const Color(0xFF1B1B1B),
                            ),
                          ),
                          SizedBox(width: iconGap),
                          Transform.translate(
                            offset: Offset(0, sin(t * pi) * 1),
                            child: Text(
                              'PLAY NOW',
                              style: AppFonts.bebasNeue(
                                fontSize: fontSize,
                                letterSpacing: letterSpacing,
                                color: const Color(0xFF1B1B1B),
                                fontWeight: FontWeight.w800,
                                shadows: <Shadow>[
                                  Shadow(
                                    color: AppColors.goldShine.withValues(alpha: 0.6),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

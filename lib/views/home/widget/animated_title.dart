import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/theme/app_colors.dart';

class AnimatedTitle extends StatefulWidget {
  const AnimatedTitle({super.key, required this.fontSize});
  final double fontSize;

  @override
  State<AnimatedTitle> createState() => _AnimatedTitleState();
}

class _AnimatedTitleState extends State<AnimatedTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine;

  @override
  void initState() {
    super.initState();
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedBuilder(
          animation: _shine,
          builder: (final BuildContext context, final Widget? child) {
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (final Rect bounds) {
                final double t = _shine.value;
                return LinearGradient(
                  begin: Alignment(-1 + t * 3, -0.6),
                  end: Alignment(-0.4 + t * 3, 0.6),
                  colors: const <Color>[
                    AppColors.goldDeep,
                    AppColors.goldBright,
                    AppColors.goldShine,
                    AppColors.goldBright,
                    AppColors.goldDeep,
                  ],
                  stops: const <double>[0.0, 0.4, 0.5, 0.6, 1.0],
                ).createShader(bounds);
              },
              child: Text(
                'MINI KICKERS',
                style: AppFonts.bebasNeue(
                  fontSize: widget.fontSize,
                  letterSpacing: widget.fontSize * 0.08,
                  height: 1.0,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(
                      color: AppColors.goldBright.withValues(alpha: 0.55),
                      blurRadius: 30,
                    ),
                    const Shadow(
                      color: Colors.black87,
                      blurRadius: 6,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                AppColors.brandRed.withValues(alpha: 0.15),
                AppColors.brandRed.withValues(alpha: 0.35),
                AppColors.brandRed.withValues(alpha: 0.15),
              ],
            ),
            border: Border.all(
              color: AppColors.brandRed.withValues(alpha: 0.6),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            "INDIA'S #1 INDOOR FOOTBALL BOARD GAME",
            style: TextStyle(
              color: Colors.white,
              letterSpacing: 2.5,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

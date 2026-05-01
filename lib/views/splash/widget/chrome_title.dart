import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';

/// Bold "MINI KICKERS" title with chrome-gold gradient via [ShaderMask].
/// Lightweight: one shader applied per frame, no blur.
class ChromeTitle extends StatelessWidget {
  const ChromeTitle({
    super.key,
    required this.progress, // 0..1 reveal
    required this.fontSize,
  });

  final double progress;
  final double fontSize;

  @override
  Widget build(final BuildContext context) {
    if (progress <= 0) return const SizedBox.shrink();
    final double t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, 30 * (1 - t)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Line(text: 'MINI', fontSize: fontSize),
            _Line(text: 'KICKERS', fontSize: fontSize),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, required this.fontSize});
  final String text;
  final double fontSize;

  @override
  Widget build(final BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (final Rect bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          AppColors.goldShine,
          AppColors.goldBright,
          AppColors.goldDeep,
        ],
        stops: <double>[0.0, 0.5, 1.0],
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppFonts.bebasNeue(
          fontSize: fontSize,
          letterSpacing: fontSize * 0.07,
          height: 0.95,
          color: Colors.white,
          shadows: <Shadow>[
            Shadow(
              color: AppColors.goldBright.withValues(alpha: 0.85),
              blurRadius: fontSize * 0.4,
            ),
          ],
        ),
      ),
    );
  }
}

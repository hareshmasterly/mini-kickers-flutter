import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';

/// Move-target highlight for legal cells.
///
/// 1:1 visual match for the web's `.cell.highlight::before` style:
///   • 3px inset
///   • 2px DASHED border in `rgba(200,240,64,0.85)`
///   • 4px corner radius
///   • Faint `rgba(200,240,64,0.1)` fill
///   • Opacity pulses 0.7 ↔ 1.0 every ~1s
///
/// Crucially: **no glow, no box-shadow**. Earlier versions had a 6-18 px
/// pulsing shadow that bled into adjacent cells, making 6 legal targets
/// look like a 12+ cell blob — players read this as "wrong cells
/// highlighted". This implementation stays inside the cell bounds.
class AnimatedHighlight extends StatefulWidget {
  const AnimatedHighlight({
    super.key,
    required this.onTap,
    required this.indexDelay,
  });

  final VoidCallback onTap;
  final int indexDelay;

  @override
  State<AnimatedHighlight> createState() => _AnimatedHighlightState();
}

class _AnimatedHighlightState extends State<AnimatedHighlight>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    Future<void>.delayed(
      Duration(milliseconds: 24 * widget.indexDelay),
      () {
        if (!mounted) return;
        _enter.forward();
        _pulse.repeat(reverse: true);
      },
    );
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      // The cell-sized hit-target is the OUTER box; the painted dashed
      // outline lives inside it via the 3px margin.
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_enter, _pulse]),
        builder: (final BuildContext context, final Widget? child) {
          // Web pulse: opacity 0.7 → 1.0 → 0.7 every ~1s.
          final double e = Curves.easeOut.transform(
            _enter.value.clamp(0.0, 1.0),
          );
          final double pulseT = _pulse.value;
          final double opacity = e * (0.7 + 0.3 * pulseT);
          return Opacity(
            opacity: opacity,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: CustomPaint(
                painter: _DashedRectPainter(
                  color: AppColors.accent.withValues(alpha: 0.85),
                  fillColor: AppColors.accent.withValues(alpha: 0.1),
                  strokeWidth: 2,
                  radius: 4,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Web-faithful dashed rounded rectangle. Uses a `PathMetric` walk so
/// dashes follow the rounded corners cleanly — no overshoot, no gaps at
/// the corners.
class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({
    required this.color,
    required this.fillColor,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final Color fillColor;
  final double strokeWidth;
  final double radius;

  // Dash + gap lengths — chosen to read like CSS `border: 2px dashed` in
  // Chrome (roughly equal length).
  static const double _dashLen = 5;
  static const double _gapLen = 4;

  @override
  void paint(final Canvas canvas, final Size size) {
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    // 1) Faint fill inside the rounded rect.
    final Paint fill = Paint()..color = fillColor;
    canvas.drawRRect(rrect, fill);

    // 2) Dashed stroke around the perimeter.
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final Path src = Path()..addRRect(rrect);
    for (final ui in src.computeMetrics()) {
      double dist = 0;
      while (dist < ui.length) {
        final double next = dist + _dashLen;
        final Path seg = ui.extractPath(dist, next.clamp(0, ui.length));
        canvas.drawPath(seg, stroke);
        dist = next + _gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant final _DashedRectPainter old) =>
      old.color != color ||
      old.fillColor != fillColor ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius;
}

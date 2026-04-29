import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/amazon_launcher.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/responsive.dart';

/// Promotional "Buy on Amazon" card shown after every goal — mirrors the
/// popup on minikickers.in. The caller (GameScreen) controls when it shows
/// vs hides; the card itself is a stateless modal with a dismiss callback.
///
/// Adaptive layout:
///   • Tall canvas (e.g. tablet portrait): vertical card with hero football
///     on top, copy below, big CTA at the bottom.
///   • Short canvas (mobile landscape): horizontal split — football on the
///     left, copy + CTA stacked on the right. Tightly padded to never
///     overflow.
///
/// Both layouts are wrapped in `SingleChildScrollView` so any extreme aspect
/// ratio still scrolls instead of clipping.
class FirstGoalAdOverlay extends StatefulWidget {
  const FirstGoalAdOverlay({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  State<FirstGoalAdOverlay> createState() => _FirstGoalAdOverlayState();
}

class _FirstGoalAdOverlayState extends State<FirstGoalAdOverlay>
    with TickerProviderStateMixin {
  static const Duration _autoCloseAfter = Duration(seconds: 10);

  late final AnimationController _entry;
  late final AnimationController _ambient;
  late final AnimationController _countdown;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    // 10-second auto-dismiss timer. Drives both the top progress bar
    // and the "Closes in Ns" label. Stopped (not reset) when the user
    // taps BUY so they can return from Amazon and still manually close.
    _countdown = AnimationController(vsync: this, duration: _autoCloseAfter)
      ..forward()
      ..addStatusListener((final AnimationStatus s) {
        if (s == AnimationStatus.completed && mounted && !_dismissing) {
          _close();
        }
      });
    AudioHelper.whistle();
  }

  @override
  void dispose() {
    _entry.dispose();
    _ambient.dispose();
    _countdown.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_dismissing) return;
    _dismissing = true;
    _countdown.stop();
    AudioHelper.select();
    await _entry.reverse();
    if (!mounted) return;
    widget.onDismiss();
  }

  Future<void> _onBuy() async {
    // Pause the auto-close — user is engaging. They can dismiss
    // manually via the close X or LATER when they return.
    _countdown.stop();
    AudioHelper.hapticHeavy();
    await AmazonLauncher.openProductPage();
  }

  @override
  Widget build(final BuildContext context) {
    return LayoutBuilder(
      builder: (final BuildContext context, final BoxConstraints cons) {
        final bool compact = Responsive.isCompactBox(cons);
        // Card width: wider when horizontal (560), capped narrower vertically.
        final double cardMaxWidth = compact ? 560 : 460;
        final double cardWidth = min(cardMaxWidth, cons.maxWidth - 32);
        final double maxCardHeight = cons.maxHeight - 24;

        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _entry,
            _ambient,
            _countdown,
          ]),
          builder: (final BuildContext context, final Widget? child) {
            final double t = Curves.easeOutCubic.transform(
              _entry.value.clamp(0.0, 1.0),
            );
            final double scaleT = Curves.elasticOut.transform(
              _entry.value.clamp(0.0, 1.0),
            );
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // ── Backdrop (tap to dismiss) ──
                GestureDetector(
                  onTap: _close,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8 * t, sigmaY: 8 * t),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.72 * t),
                    ),
                  ),
                ),
                // ── Sunburst behind card ──
                Center(
                  child: Opacity(
                    opacity: 0.45 * t,
                    child: Transform.rotate(
                      angle: _ambient.value * 2 * pi,
                      child: CustomPaint(
                        size: Size(cardWidth * 1.8, cardWidth * 1.8),
                        painter: _SunburstPainter(),
                      ),
                    ),
                  ),
                ),
                // ── Card ──
                Center(
                  child: Transform.scale(
                    scale: 0.6 + scaleT * 0.4,
                    child: Opacity(
                      opacity: t,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: cardWidth,
                          maxHeight: maxCardHeight,
                        ),
                        child: _Card(
                          ambient: _ambient.value,
                          countdownValue: _countdown.value,
                          autoCloseSeconds: _autoCloseAfter.inSeconds,
                          compact: compact,
                          onBuy: _onBuy,
                          onLater: _close,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.ambient,
    required this.countdownValue,
    required this.autoCloseSeconds,
    required this.compact,
    required this.onBuy,
    required this.onLater,
  });

  final double ambient;

  /// 0.0 = full bar / "Closes in 10s"; 1.0 = empty / about to close.
  final double countdownValue;
  final int autoCloseSeconds;
  final bool compact;
  final VoidCallback onBuy;
  final VoidCallback onLater;

  @override
  Widget build(final BuildContext context) {
    final double pulse = 0.5 + 0.5 * sin(ambient * 2 * pi * 1.4);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF112418), Color(0xFF06140C)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.goldBright.withValues(alpha: 0.85),
          width: 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.goldDeep.withValues(alpha: 0.55 + pulse * 0.25),
            blurRadius: 50 + pulse * 18,
            spreadRadius: 2,
          ),
          const BoxShadow(
            color: Colors.black87,
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: <Widget>[
            // Subtle inner radial glow behind the football.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(compact ? -0.7 : 0, compact ? 0 : -0.55),
                    radius: 0.95,
                    colors: <Color>[
                      AppColors.brandYellow.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 0,
                compact ? 16 : 0,
                compact ? 16 : 0,
                compact ? 14 : 18,
              ),
              child: compact
                  ? _CompactBody(
                      ambient: ambient,
                      pulse: pulse,
                      countdownValue: countdownValue,
                      autoCloseSeconds: autoCloseSeconds,
                      onBuy: onBuy,
                      onLater: onLater,
                    )
                  : _TallBody(
                      ambient: ambient,
                      pulse: pulse,
                      countdownValue: countdownValue,
                      autoCloseSeconds: autoCloseSeconds,
                      onBuy: onBuy,
                      onLater: onLater,
                    ),
            ),
            // Top-edge countdown progress bar — shrinks from full width
            // as the auto-close timer runs out. Manual close X has been
            // removed; users dismiss via the countdown, MAYBE LATER, or
            // tapping the backdrop.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _CountdownProgressBar(value: countdownValue),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TALL (portrait / tablet) layout
// ─────────────────────────────────────────────────────────────────────────

class _TallBody extends StatelessWidget {
  const _TallBody({
    required this.ambient,
    required this.pulse,
    required this.countdownValue,
    required this.autoCloseSeconds,
    required this.onBuy,
    required this.onLater,
  });

  final double ambient;
  final double pulse;
  final double countdownValue;
  final int autoCloseSeconds;
  final VoidCallback onBuy;
  final VoidCallback onLater;

  @override
  Widget build(final BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Header(ambient: ambient),
        const SizedBox(height: 8),
        const _Body(),
        const SizedBox(height: 18),
        _BuyButton(onTap: onBuy, pulse: pulse),
        const SizedBox(height: 8),
        // _LaterButton(onTap: onLater),
        // const SizedBox(height: 4),
        _CountdownLabel(value: countdownValue, totalSeconds: autoCloseSeconds),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ambient});

  final double ambient;

  @override
  Widget build(final BuildContext context) {
    final double bob = sin(ambient * 2 * pi) * 6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 4),
      child: Column(
        children: <Widget>[
          _Eyebrow(),
          const SizedBox(height: 14),
          _Headline(fontSize: 38),
          const SizedBox(height: 4),
          _Subtitle(),
          const SizedBox(height: 12),
          // Floating product hero (photo of the physical board game).
          Transform.translate(
            offset: Offset(0, bob),
            child: const _ProductHero(width: 150),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(final BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 6, 28, 0),
      child: Column(
        children: <Widget>[
          Text(
            'MINI KICKERS — THE BOARD GAME',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'BebasNeue',
              fontSize: 20,
              letterSpacing: 2,
              color: Colors.white,
              height: 1.0,
            ),
          ),
          SizedBox(height: 10),
          _BulletRow(
            icon: Icons.sports_soccer_rounded,
            text: 'Real wood board, real dice, real goals',
          ),
          SizedBox(height: 6),
          _BulletRow(
            icon: Icons.group_rounded,
            text: 'Perfect for family game nights',
          ),
          SizedBox(height: 6),
          _BulletRow(
            icon: Icons.flash_on_rounded,
            text: 'No batteries — travel-friendly',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// COMPACT (landscape / short height) layout
// ─────────────────────────────────────────────────────────────────────────

class _CompactBody extends StatelessWidget {
  const _CompactBody({
    required this.ambient,
    required this.pulse,
    required this.countdownValue,
    required this.autoCloseSeconds,
    required this.onBuy,
    required this.onLater,
  });

  final double ambient;
  final double pulse;
  final double countdownValue;
  final int autoCloseSeconds;
  final VoidCallback onBuy;
  final VoidCallback onLater;

  @override
  Widget build(final BuildContext context) {
    final double bob = sin(ambient * 2 * pi) * 4;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // Product hero on the left (compact landscape).
        Transform.translate(
          offset: Offset(0, bob),
          child: const _ProductHero(width: 120),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Eyebrow(),
              const SizedBox(height: 8),
              _Headline(fontSize: 28, align: TextAlign.left),
              const SizedBox(height: 4),
              _Subtitle(align: TextAlign.left),
              const SizedBox(height: 8),
              _BulletRow(
                icon: Icons.sports_soccer_rounded,
                text: 'Real wood board · real dice · real goals',
                fontSize: 12,
              ),
              const SizedBox(height: 4),
              _BulletRow(
                icon: Icons.flash_on_rounded,
                text: 'No batteries — travel-friendly',
                fontSize: 12,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _BuyButton(
                      onTap: onBuy,
                      pulse: pulse,
                      compact: true,
                    ),
                  ),
                  // const SizedBox(width: 8),
                  // _LaterButton(onTap: onLater, compact: true),
                ],
              ),
              const SizedBox(height: 4),
              // Center the countdown specifically — the rest of this
              // column is left-aligned (crossAxisAlignment.start), so
              // without an explicit Center the label hugs the left
              // edge instead of sitting under the BUY button.
              Align(
                alignment: Alignment.center,
                child: _CountdownLabel(
                  value: countdownValue,
                  totalSeconds: autoCloseSeconds,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared atoms
// ─────────────────────────────────────────────────────────────────────────

class _Eyebrow extends StatelessWidget {
  @override
  Widget build(final BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brandYellow.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brandYellow.withValues(alpha: 0.5)),
      ),
      child: Text(
        '⚽  GOAL SCORED!',
        style: TextStyle(
          color: AppColors.brandYellow.withValues(alpha: 0.95),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.fontSize, this.align = TextAlign.center});

  final double fontSize;
  final TextAlign align;

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
        stops: <double>[0.0, 0.55, 1.0],
      ).createShader(bounds),
      child: Text(
        'LOVE THE GAME?',
        textAlign: align,
        style: AppFonts.bebasNeue(
          fontSize: fontSize,
          letterSpacing: 3,
          color: Colors.white,
          height: 0.95,
          shadows: <Shadow>[
            Shadow(
              color: AppColors.goldBright.withValues(alpha: 0.6),
              blurRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({this.align = TextAlign.center});

  final TextAlign align;

  @override
  Widget build(final BuildContext context) {
    return Text(
      'Take it from screen to table.',
      textAlign: align,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.78),
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

/// Product hero — a rounded-rectangle photo of the physical Mini Kickers
/// board game, with a glowing gold frame so it lifts off the dark card.
///
/// `width` controls horizontal size; the image is square (1:1 crop of the
/// product shot), giving a clean tile that fits both portrait and compact
/// landscape layouts.
class _ProductHero extends StatelessWidget {
  const _ProductHero({required this.width});

  final double width;

  @override
  Widget build(final BuildContext context) {
    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.goldBright.withValues(alpha: 0.85),
          width: 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.goldBright.withValues(alpha: 0.4),
            blurRadius: 28,
            spreadRadius: 2,
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          'assets/png/img_product_hero.jpg',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({
    required this.icon,
    required this.text,
    this.fontSize = 13,
  });

  final IconData icon;
  final String text;
  final double fontSize;

  @override
  Widget build(final BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: AppColors.brandYellow, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _BuyButton extends StatefulWidget {
  const _BuyButton({
    required this.onTap,
    required this.pulse,
    this.compact = false,
  });

  final VoidCallback onTap;
  final double pulse;
  final bool compact;

  @override
  State<_BuyButton> createState() => _BuyButtonState();
}

class _BuyButtonState extends State<_BuyButton> {
  bool _pressed = false;

  @override
  Widget build(final BuildContext context) {
    final double vPad = widget.compact ? 11 : 14;
    final double hPad = widget.compact ? 14 : 18;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 20),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: GestureDetector(
          onTapDown: (final _) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (final _) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFFFC107), Color(0xFFFF9800)],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 2,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(
                    0xFFFF9800,
                  ).withValues(alpha: 0.55 + widget.pulse * 0.35),
                  blurRadius: 18 + widget.pulse * 10,
                  spreadRadius: 1 + widget.pulse * 1.5,
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: widget.compact ? 24 : 30,
                  height: widget.compact ? 24 : 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      'a',
                      style: AppFonts.bebasNeue(
                        fontSize: widget.compact ? 20 : 26,
                        color: const Color(0xFF131921),
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'BUY ON AMAZON',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: widget.compact ? 9 : 10,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'GET THE BOARD GAME',
                        style: AppFonts.bebasNeue(
                          color: Colors.white,
                          fontSize: widget.compact ? 16 : 20,
                          letterSpacing: 1.4,
                          height: 1.0,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: widget.compact ? 18 : 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LaterButton extends StatelessWidget {
  const _LaterButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.65),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 18,
          vertical: 6,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        compact ? 'LATER' : 'MAYBE LATER',
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Thin gradient bar pinned to the very top of the card. Width shrinks
/// from 100% → 0% as the auto-close timer runs out.
class _CountdownProgressBar extends StatelessWidget {
  const _CountdownProgressBar({required this.value});

  /// 0.0 = full bar; 1.0 = bar gone (timer expired).
  final double value;

  @override
  Widget build(final BuildContext context) {
    return SizedBox(
      height: 3,
      child: ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (1 - value).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[AppColors.limeBright, AppColors.brandYellow],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.limeBright.withValues(alpha: 0.7),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Closes in Ns" small caption below the buttons. Mirrors the web ad
/// — gives users a visible countdown alongside the progress bar.
class _CountdownLabel extends StatelessWidget {
  const _CountdownLabel({required this.value, required this.totalSeconds});

  final double value;
  final int totalSeconds;

  @override
  Widget build(final BuildContext context) {
    final int remaining = (totalSeconds * (1 - value)).ceil().clamp(
      0,
      totalSeconds,
    );
    return Text(
      'Closes in ${remaining}s',
      textAlign: .center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 10,
        letterSpacing: 1,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Soft sunburst behind the card — pure paint, very cheap (16 wedges).
class _SunburstPainter extends CustomPainter {
  @override
  void paint(final Canvas canvas, final Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double r = size.width / 2;
    final Paint wedge = Paint()..style = PaintingStyle.fill;
    const int rays = 16;
    for (int i = 0; i < rays; i++) {
      final double a0 = (i / rays) * 2 * pi;
      final double a1 = a0 + (pi / rays) * 0.55;
      final Path p = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + cos(a0) * r, center.dy + sin(a0) * r)
        ..lineTo(center.dx + cos(a1) * r, center.dy + sin(a1) * r)
        ..close();
      wedge.shader = RadialGradient(
        colors: <Color>[
          AppColors.brandYellow.withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawPath(p, wedge);
    }
  }

  @override
  bool shouldRepaint(covariant final CustomPainter oldDelegate) => false;
}

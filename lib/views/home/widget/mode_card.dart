import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/audio_helper.dart';

/// One of the two primary "pick your match mode" cards on the home
/// screen (VS AI / PASS & PLAY). Carries the same premium gold +
/// glow language as the previous single PLAY button so the home
/// screen still feels premium — just on two surfaces instead of one.
///
/// Sizing follows the home-screen tier scheme:
///   • `ultraShort` (h < 320) — chip hidden, smallest fonts
///   • `compact`/`short` (h < 460) — landscape phones, dense
///   • `tablet` (w ≥ 720) — generous, big icon and chip
///   • otherwise — regular phone landscape
///
/// `glowColor` tints the outer halo so the AI card and the
/// pass-and-play card don't read as identical mirrors.
class ModeCard extends StatefulWidget {
  const ModeCard({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.glowColor,
    required this.onTap,
    this.chipText,
    this.compact = false,
    this.ultraShort = false,
    this.isTablet = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color glowColor;
  final VoidCallback onTap;

  /// Optional small chip near the bottom (e.g. current AI difficulty
  /// "MEDIUM"). Auto-hidden on ultraShort screens.
  final String? chipText;

  final bool compact;
  final bool ultraShort;
  final bool isTablet;

  @override
  State<ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<ModeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    // Sizing tiers — keep aggressive on ultraShort so two cards still
    // fit alongside the title + action row on iPhone SE landscape
    // (375h).
    final double iconSize = widget.ultraShort
        ? 22
        : widget.compact
        ? 30
        : widget.isTablet
        ? 56
        : 40;
    final double labelFont = widget.ultraShort
        ? 16
        : widget.compact
        ? 22
        : widget.isTablet
        ? 36
        : 28;
    final double subtitleFont = widget.ultraShort
        ? 9
        : widget.compact
        ? 10
        : widget.isTablet
        ? 14
        : 12;
    final double padV = widget.ultraShort
        ? 6
        : widget.compact
        ? 10
        : widget.isTablet
        ? 22
        : 14;
    final double padH = widget.ultraShort
        ? 10
        : widget.compact
        ? 12
        : widget.isTablet
        ? 24
        : 16;
    final double radius = widget.ultraShort ? 14 : (widget.isTablet ? 24 : 18);
    final double gapAfterIcon = widget.ultraShort
        ? 4
        : widget.compact
        ? 6
        : widget.isTablet
        ? 12
        : 8;
    final double gapAfterLabel = widget.ultraShort ? 1 : 2;
    final double gapBeforeChip = widget.ultraShort
        ? 0
        : widget.compact
        ? 6
        : widget.isTablet
        ? 12
        : 8;

    final bool showChip = widget.chipText != null && !widget.ultraShort;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (final BuildContext context, final Widget? child) {
        final double t = _pulse.value;
        return AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: GestureDetector(
            onTapDown: (final _) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (final _) {
              setState(() => _pressed = false);
              AudioHelper.select();
              widget.onTap();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    AppColors.goldShine,
                    AppColors.goldBright,
                    Color(0xFFFF9800),
                  ],
                  stops: <double>[0.0, 0.55, 1.0],
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: <BoxShadow>[
                  // Mode-tinted halo — pulses softly so the card
                  // feels alive without being noisy.
                  BoxShadow(
                    color: widget.glowColor.withValues(alpha: 0.42 + t * 0.25),
                    blurRadius: widget.compact ? 16 + t * 8 : 22 + t * 12,
                    spreadRadius: 1 + t * 2,
                  ),
                  // Gold base glow (constant) — keeps the premium
                  // gold language even when the tinted halo dips.
                  BoxShadow(
                    color: AppColors.goldBright.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                  const BoxShadow(
                    color: Colors.black54,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                alignment: .center,
                children: <Widget>[
                  // Subtle radial gloss highlight at the top-left
                  // corner — gives the gold a "polished metal" feel
                  // that the flat gradient on its own doesn't have.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          gradient: RadialGradient(
                            center: const Alignment(-0.7, -0.9),
                            radius: 1.0,
                            colors: <Color>[
                              Colors.white.withValues(alpha: 0.35),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const <double>[0.0, 0.55],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: .center,
                    children: <Widget>[
                      _IconBadge(
                        icon: widget.icon,
                        iconSize: iconSize,
                        ultraShort: widget.ultraShort,
                      ),
                      SizedBox(height: gapAfterIcon),
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: AppFonts.bebasNeue(
                          fontSize: labelFont,
                          letterSpacing: widget.ultraShort ? 1.5 : 3,
                          color: const Color(0xFF1B1B1B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: gapAfterLabel),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF1B1B1B).withValues(alpha: 0.7),
                          fontSize: subtitleFont,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (showChip) ...<Widget>[
                        SizedBox(height: gapBeforeChip),
                        _Chip(
                          text: widget.chipText!,
                          compact: widget.compact,
                          isTablet: widget.isTablet,
                        ),
                      ],
                    ],
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

/// Dark circular backdrop behind the icon. Adds depth and frames the
/// glyph against the gold gradient — without it, the bare icon
/// floats and competes with the label for visual weight.
class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.iconSize,
    required this.ultraShort,
  });

  final IconData icon;
  final double iconSize;
  final bool ultraShort;

  @override
  Widget build(final BuildContext context) {
    final double diameter = iconSize * 1.6;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.25, -0.35),
          colors: <Color>[const Color(0xFF333333), const Color(0xFF111111)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: ultraShort ? 6 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: AppColors.goldShine,
          shadows: <Shadow>[
            Shadow(
              color: AppColors.goldBright.withValues(alpha: 0.6),
              blurRadius: 12,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.compact,
    required this.isTablet,
  });

  final String text;
  final bool compact;
  final bool isTablet;

  @override
  Widget build(final BuildContext context) {
    final double font = compact ? 9 : (isTablet ? 12 : 10);
    final double padV = compact ? 3 : (isTablet ? 5 : 4);
    final double padH = compact ? 8 : (isTablet ? 14 : 10);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: font,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

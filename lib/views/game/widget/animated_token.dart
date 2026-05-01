import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/team_colors.dart';

class AnimatedToken extends StatefulWidget {
  const AnimatedToken({
    super.key,
    required this.token,
    required this.cell,
    required this.isSelected,
    required this.isSelectable,
    this.onTap,
    this.isActiveTeam = false,
  });

  final Token token;
  final double cell;

  /// User has tapped this exact token — show the bright gold sweep ring.
  final bool isSelected;

  /// User can tap this token *right now* (move phase, no selection yet).
  /// Drives the bright dashed ring + pulse glow.
  final bool isSelectable;

  /// Token belongs to the team whose turn it is, but we're not in a
  /// "tap-to-select" moment (e.g. before dice is rolled). Drives a
  /// dimmer, calmer dashed ring so the active side is identifiable on
  /// the board without inviting a tap.
  final bool isActiveTeam;

  /// Tap handler. When `null`, the token is rendered as normal but
  /// the GestureDetector ignores taps. Used to gate "you can't select
  /// this" cases (opponent's tokens, AI's tokens, non-move phases) so
  /// the user gets no audio / animation feedback for taps that would
  /// be rejected by the bloc anyway.
  final VoidCallback? onTap;

  @override
  State<AnimatedToken> createState() => _AnimatedTokenState();
}

class _AnimatedTokenState extends State<AnimatedToken>
    with TickerProviderStateMixin {
  late final AnimationController _arrival;
  late final AnimationController _selectableLoop;
  late final AnimationController _dashSpin;
  late final AnimationController _selectionRing;
  Pos? _previousPos;

  @override
  void initState() {
    super.initState();
    _arrival = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _selectableLoop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _dashSpin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _selectionRing = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    if (widget.isSelectable) {
      _selectableLoop.repeat(reverse: true);
    }
    if (widget.isSelectable || widget.isActiveTeam) {
      _dashSpin.repeat();
    }
    if (widget.isSelected) _selectionRing.repeat();
    _previousPos = Pos(widget.token.c, widget.token.r);
  }

  @override
  void didUpdateWidget(covariant final AnimatedToken old) {
    super.didUpdateWidget(old);
    final Pos cur = Pos(widget.token.c, widget.token.r);
    if (cur != _previousPos) {
      _previousPos = cur;
      _arrival
        ..reset()
        ..forward();
    }
    // The token-glow pulse follows isSelectable only — it's the
    // "tap me" cue and shouldn't fire on the calmer active-team state.
    if (widget.isSelectable && !old.isSelectable) {
      _selectableLoop.repeat(reverse: true);
    } else if (!widget.isSelectable && old.isSelectable) {
      _selectableLoop
        ..stop()
        ..reset();
    }
    // The dashed ring spins for both states — selectable and
    // active-team-only — so the active side is always identifiable.
    final bool wantsRing = widget.isSelectable || widget.isActiveTeam;
    final bool hadRing = old.isSelectable || old.isActiveTeam;
    if (wantsRing && !hadRing) {
      _dashSpin.repeat();
    } else if (!wantsRing && hadRing) {
      _dashSpin
        ..stop()
        ..reset();
    }
    if (widget.isSelected && !old.isSelected) {
      _selectionRing.repeat();
    } else if (!widget.isSelected && old.isSelected) {
      _selectionRing
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    _selectableLoop.dispose();
    _dashSpin.dispose();
    _selectionRing.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final Color color = TeamColors.primary(widget.token.team);
    final Color borderColor = TeamColors.light(widget.token.team);
    // Web parity: dashed ring uses the team-light colour directly (no lerp).
    final Color dashColor = borderColor;
    final double size = widget.cell * 0.67;
    // Web parity: ring is 0.89 × cell.
    final double dashRingSize = widget.cell * 0.89;

    // Position the AnimatedPositioned at the FULL cell so the GestureDetector
    // catches taps anywhere in the cell (mobile users were missing the
    // smaller visible token shape — `size` is only 67% of the cell). The
    // visible token is then centered inside via Center+SizedBox so it
    // looks identical to before; only the hit area changed.
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      left: widget.token.c * widget.cell,
      top: widget.token.r * widget.cell,
      width: widget.cell,
      height: widget.cell,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: SizedBox(
            width: size,
            height: size,
            child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _arrival,
            _selectableLoop,
            _dashSpin,
            _selectionRing,
          ]),
          builder: (final BuildContext context, final Widget? child) {
            final double a = _arrival.value;
            final double arrivalScale =
                a == 0 ? 1.0 : 1.0 + sin(a * pi) * 0.25;
            final double pulse = sin(_selectableLoop.value * pi);
            final double selectableScale =
                widget.isSelectable ? 1.0 + pulse * 0.07 : 1.0;
            final double selectScale = widget.isSelected ? 1.12 : 1.0;
            final double finalScale =
                arrivalScale * selectableScale * selectScale;

            return Transform.scale(
              scale: finalScale,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: <Widget>[
                  // Dashed ring: bright variant when the user can tap
                  // the token, dimmer/thinner variant when the team is
                  // simply active (e.g. between turns, before the dice
                  // is rolled). The selected token gets a different
                  // gold sweep — no dashed ring.
                  if (!widget.isSelected &&
                      (widget.isSelectable || widget.isActiveTeam))
                    IgnorePointer(
                      child: SizedBox(
                        width: dashRingSize,
                        height: dashRingSize,
                        child: CustomPaint(
                          painter: _DashedRingPainter(
                            color: dashColor.withValues(
                              alpha: widget.isSelectable ? 0.85 : 0.5,
                            ),
                            rotation: _dashSpin.value * pi * 2,
                            strokeWidth: widget.isSelectable ? 2.5 : 1.8,
                          ),
                        ),
                      ),
                    ),
                  if (widget.isSelected)
                    Transform.rotate(
                      angle: _selectionRing.value * pi * 2,
                      child: Container(
                        width: size * 1.35,
                        height: size * 1.35,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: <Color>[
                              AppColors.accent.withValues(alpha: 0),
                              AppColors.accent,
                              AppColors.accent.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.4),
                        colors: <Color>[
                          Color.lerp(color, Colors.white, 0.35)!,
                          color,
                        ],
                      ),
                      border: Border.all(color: borderColor, width: 2.5),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: color.withValues(
                            alpha: widget.isSelectable
                                ? 0.7 + pulse * 0.3
                                : 0.55,
                          ),
                          blurRadius:
                              widget.isSelectable ? 14 + pulse * 10 : 10,
                          spreadRadius: widget.isSelectable ? 1 : 0,
                          offset: const Offset(0, 3),
                        ),
                        if (widget.isSelected)
                          const BoxShadow(
                            color: AppColors.accent,
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _firstLetter(TeamColors.name(widget.token.team)),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.cell * 0.24,
                          fontWeight: FontWeight.w800,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
            ),
          ),
        ),
      ),
    );
  }
}

String _firstLetter(final String s) {
  final String t = s.trim();
  if (t.isEmpty) return '?';
  return t[0].toUpperCase();
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({
    required this.color,
    required this.rotation,
    required this.strokeWidth,
  });

  final Color color;
  final double rotation;
  final double strokeWidth;

  // Match CSS `border: 2.5px dashed` look — roughly equal-length dashes & gaps,
  // count derived from circumference / (2 × strokeWidth). 14 reads close to
  // Chrome's rendering of the web reference.
  static const int _dashCount = 14;
  static const double _gapRatio = 0.5; // dash and gap equal length

  @override
  void paint(final Canvas canvas, final Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width - strokeWidth) / 2;

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt; // CSS dashed uses square caps, not round

    final double segment = (2 * pi) / _dashCount;
    final double dashAngle = segment * (1 - _gapRatio);

    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    for (int i = 0; i < _dashCount; i++) {
      final double startAngle = rotation + i * segment;
      canvas.drawArc(rect, startAngle, dashAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant final _DashedRingPainter old) =>
      old.color != color ||
      old.rotation != rotation ||
      old.strokeWidth != strokeWidth;
}

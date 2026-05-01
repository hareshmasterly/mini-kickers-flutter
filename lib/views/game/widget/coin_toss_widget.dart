import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/team_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/views/game/widget/team_setup_strip.dart';

class CoinTossHost extends StatelessWidget {
  const CoinTossHost({super.key});

  @override
  Widget build(final BuildContext context) {
    return BlocBuilder<GameBloc, GameState>(
      buildWhen: (final GameState p, final GameState n) =>
          p.phase != n.phase,
      builder: (final BuildContext context, final GameState state) {
        if (state.phase != GamePhase.coinToss) return const SizedBox.shrink();
        return CoinTossWidget(
          onComplete: (final Team winner) {
            context.read<GameBloc>().add(
                  GameEvent.coinTossComplete(winner: winner),
                );
          },
        );
      },
    );
  }
}

class CoinTossWidget extends StatefulWidget {
  const CoinTossWidget({super.key, required this.onComplete});

  final void Function(Team winner) onComplete;

  @override
  State<CoinTossWidget> createState() => _CoinTossWidgetState();
}

class _CoinTossWidgetState extends State<CoinTossWidget>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _idle;
  late final AnimationController _flip;
  late final AnimationController _result;
  Team? _winner;
  bool _isFlipping = false;
  bool _showResult = false;
  static final Random _rng = Random.secure();
  static int _tossCounter = 0;

  Team _pickWinner() {
    _tossCounter++;
    final int micro = DateTime.now().microsecondsSinceEpoch;
    final int r1 = _rng.nextInt(0x7FFFFFFF);
    final int r2 = _rng.nextInt(0x7FFFFFFF);
    final int combined = micro ^ r1 ^ (r2 << 1) ^ (_tossCounter * 7919);
    return combined.isEven ? Team.red : Team.blue;
  }

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _result = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _entry.dispose();
    _idle.dispose();
    _flip.dispose();
    _result.dispose();
    super.dispose();
  }

  Future<void> _doFlip() async {
    if (_isFlipping) return;
    AudioHelper.select();
    AudioHelper.coinFlip();
    final Team rolled = _pickWinner();
    if (kDebugMode) debugPrint('Coin toss → ${rolled.name}');
    setState(() {
      _isFlipping = true;
      _winner = rolled;
      _showResult = false;
    });

    await _flip.forward(from: 0);
    AudioHelper.diceResult();

    setState(() => _showResult = true);
    await _result.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    if (!mounted) return;
    widget.onComplete(_winner!);
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: _entry,
      builder: (final BuildContext context, final Widget? child) {
        final double t = Curves.easeOutCubic.transform(_entry.value);
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
              child: Container(
                color: Colors.black.withValues(alpha: 0.7 * t),
              ),
            ),
            // LayoutBuilder + SingleChildScrollView is a safety net so
            // the card never overflows the viewport. We use a Column
            // (not Center) inside ConstrainedBox because Center expands
            // to fill its parent and would clip an oversized child
            // without the SCV knowing it should scroll. Column with
            // mainAxisSize.min reports its actual content height, so
            // the SCV correctly enables scrolling when the card is
            // taller than the viewport, while mainAxisAlignment.center
            // still vertically centers the card when it fits.
            LayoutBuilder(
              builder: (
                final BuildContext context,
                final BoxConstraints constraints,
              ) {
                return SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 24 * (1 - t)),
                            child: _buildCard(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard() {
    // Three tiers:
    //   • compact — small landscape phones (h < 400 → e.g. iPhone SE)
    //   • tablet  — iPad / large screens. Requires BOTH dimensions to
    //              be generous (shortestSide ≥ 600); otherwise a wide
    //              landscape phone like Pixel 6 (915×412) would trip the
    //              tablet tier and the upsized card would overflow.
    //   • regular — everything in between (mid-size phones).
    final Size screen = MediaQuery.of(context).size;
    final bool compact = screen.height < 400;
    final bool isTablet = !compact && screen.shortestSide >= 600;

    final EdgeInsets cardPad = compact
        ? const EdgeInsets.fromLTRB(20, 14, 20, 14)
        : isTablet
            ? const EdgeInsets.fromLTRB(40, 40, 40, 36)
            : const EdgeInsets.fromLTRB(28, 22, 28, 20);
    final double titleFont = compact ? 22 : (isTablet ? 48 : 28);
    final double subtitleFont = compact ? 11 : (isTablet ? 16 : 12);
    // Tighter gaps now that the strip occupies space above the coin.
    // Compact + regular tiers are squeezed enough that we shave every
    // gap; tablet has plenty of room so it stays generous.
    final double gapAfterSubtitle = compact ? 6 : (isTablet ? 20 : 8);
    final double gapAfterStrip = compact ? 6 : (isTablet ? 22 : 10);
    final double gapAfterCoin = compact ? 8 : (isTablet ? 32 : 14);
    final double coinSize = compact ? 84 : (isTablet ? 220 : 116);
    final double idleBob = compact ? 4 : (isTablet ? 8 : 6);
    final double cardMaxWidth = isTablet ? 600 : 420;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: cardMaxWidth),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: cardPad,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF101F10),
              Color(0xFF0A150A),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.goldBright.withValues(alpha: 0.6), width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.goldBright.withValues(alpha: 0.45),
              blurRadius: 50,
              spreadRadius: 4,
            ),
            const BoxShadow(
              color: Colors.black87,
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'COIN TOSS',
              style: AppFonts.bebasNeue(
                fontSize: titleFont,
                letterSpacing: 6,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Whoever wins the toss kicks off',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: subtitleFont,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: gapAfterSubtitle),
            // Tappable team chips — surface name + palette controls
            // here so users find them in the natural pre-match moment
            // (otherwise buried in Settings). Dimmed + non-interactive
            // during the flip so it doesn't compete with the coin.
            AnimatedOpacity(
              opacity: _isFlipping || _showResult ? 0.25 : 1,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: _isFlipping || _showResult,
                child: TeamSetupStrip(compact: compact, isTablet: isTablet),
              ),
            ),
            SizedBox(height: gapAfterStrip),
            _CoinDisplay(
              flip: _flip,
              idle: _idle,
              winner: _winner,
              isFlipping: _isFlipping,
              size: coinSize,
              idleBob: idleBob,
            ),
            SizedBox(height: gapAfterCoin),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _showResult
                  ? _ResultBanner(
                      key: const ValueKey<String>('result'),
                      winner: _winner!,
                      anim: _result,
                    )
                  : _TapCta(
                      key: const ValueKey<String>('tap'),
                      onTap: _doFlip,
                      disabled: _isFlipping,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinDisplay extends StatelessWidget {
  const _CoinDisplay({
    required this.flip,
    required this.idle,
    required this.winner,
    required this.isFlipping,
    this.size = 140,
    this.idleBob = 6,
  });

  final AnimationController flip;
  final AnimationController idle;
  final Team? winner;
  final bool isFlipping;
  final double size;
  final double idleBob;

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[flip, idle]),
      builder: (final BuildContext context, final Widget? child) {
        final double bob = sin(idle.value * pi * 2) * idleBob;
        final double t = flip.value;
        final double spins = 7;
        final double easedT = isFlipping
            ? Curves.easeOutCubic.transform(t)
            : 0;
        final double angle = isFlipping ? easedT * pi * spins * 2 : 0;
        final double normalized = angle % (2 * pi);
        final bool frontVisible =
            normalized < pi / 2 || normalized > 3 * pi / 2;
        final double tilt = sin(idle.value * pi * 2) * 0.12;

        Team faceShown;
        if (!isFlipping) {
          faceShown = Team.red;
        } else {
          faceShown = frontVisible ? Team.red : Team.blue;
        }
        if (flip.isCompleted && winner != null) {
          faceShown = winner!;
        }

        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0014)
              ..rotateX(angle)
              ..rotateZ(isFlipping ? 0 : tilt),
            child: !isFlipping || frontVisible
                ? _CoinFace(team: faceShown, size: size)
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateX(pi),
                    child: _CoinFace(team: faceShown, size: size),
                  ),
          ),
        );
      },
    );
  }
}

class _CoinFace extends StatelessWidget {
  const _CoinFace({required this.team, this.size = 140});
  final Team team;
  final double size;

  @override
  Widget build(final BuildContext context) {
    final Color base = TeamColors.primary(team);
    final Color light = TeamColors.light(team);
    final String name = TeamColors.name(team);
    final String letter = name.isEmpty ? '?' : name[0].toUpperCase();
    final double letterFont = size * 0.56;
    final double margin = size * 0.085;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: <Color>[
            AppColors.goldShine,
            AppColors.goldBright,
            AppColors.goldDeep,
          ],
        ),
        border: Border.all(color: AppColors.goldShine, width: 4),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.goldBright.withValues(alpha: 0.65),
            blurRadius: 30,
            spreadRadius: 3,
          ),
          BoxShadow(
            color: base.withValues(alpha: 0.5),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Container(
        margin: EdgeInsets.all(margin),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.25, -0.35),
            colors: <Color>[
              Color.lerp(base, Colors.white, 0.45)!,
              base,
            ],
          ),
          border: Border.all(color: light, width: 2),
        ),
        child: Center(
          child: Text(
            letter,
            style: AppFonts.bebasNeue(
              fontSize: letterFont,
              letterSpacing: 2,
              color: Colors.white,
              shadows: const <Shadow>[
                Shadow(color: Colors.black38, blurRadius: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TapCta extends StatefulWidget {
  const _TapCta({super.key, required this.onTap, required this.disabled});
  final VoidCallback onTap;
  final bool disabled;

  @override
  State<_TapCta> createState() => _TapCtaState();
}

class _TapCtaState extends State<_TapCta>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (final BuildContext context, final Widget? child) {
        final double t = _pulse.value;
        return GestureDetector(
          onTap: widget.disabled ? null : widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  AppColors.goldBright,
                  Color(0xFFFF9800),
                ],
              ),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.goldBright.withValues(alpha: 0.55 + t * 0.4),
                  blurRadius: 18 + t * 16,
                  spreadRadius: 1 + t * 3,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.flip_camera_android_rounded,
                    size: 22, color: Color(0xFF1B1B1B)),
                const SizedBox(width: 8),
                Text(
                  'TAP TO FLIP',
                  style: AppFonts.bebasNeue(
                    fontSize: 22,
                    letterSpacing: 4,
                    color: const Color(0xFF1B1B1B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({super.key, required this.winner, required this.anim});
  final Team winner;
  final AnimationController anim;

  @override
  Widget build(final BuildContext context) {
    final Color color = TeamColors.primary(winner);
    final String label = '${TeamColors.name(winner)} KICKS OFF!';
    return AnimatedBuilder(
      animation: anim,
      builder: (final BuildContext context, final Widget? child) {
        final double t =
            Curves.elasticOut.transform(anim.value).clamp(0.0, 1.5);
        return Transform.scale(
          scale: 0.5 + t * 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(40),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 26,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Text(
              label,
              style: AppFonts.bebasNeue(
                fontSize: 28,
                letterSpacing: 4,
                color: Colors.white,
                shadows: <Shadow>[
                  Shadow(color: color, blurRadius: 14),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

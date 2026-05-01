import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/team_colors.dart';
import 'package:mini_kickers/utils/responsive.dart';
import 'package:mini_kickers/utils/ad_manager.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/views/game/widget/confetti_overlay.dart';

class GameOverWidget extends StatefulWidget {
  const GameOverWidget({
    super.key,
    required this.redScore,
    required this.blueScore,
    required this.onPlayAgain,
    required this.onHome,
  });

  final int redScore;
  final int blueScore;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;

  @override
  State<GameOverWidget> createState() => _GameOverWidgetState();
}

class _GameOverWidgetState extends State<GameOverWidget>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _trophyShine;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _trophyShine = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _entry.dispose();
    _trophyShine.dispose();
    super.dispose();
  }

  Team? get _winner {
    if (widget.redScore > widget.blueScore) return Team.red;
    if (widget.blueScore > widget.redScore) return Team.blue;
    return null;
  }

  @override
  Widget build(final BuildContext context) {
    final bool draw = _winner == null;
    final Color winnerColor =
        _winner != null ? TeamColors.primary(_winner!) : AppColors.muted;
    final String winnerLabel = draw
        ? "IT'S A DRAW"
        : '${TeamColors.name(_winner!)} WINS!';

    return AnimatedBuilder(
      animation: _entry,
      builder: (final BuildContext context, final Widget? child) {
        final double t = Curves.easeOutCubic.transform(_entry.value);
        final double scaleT = Curves.elasticOut
            .transform(_entry.value.clamp(0.0, 1.0))
            .clamp(0.0, 1.2);
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
              child: Container(
                color: Colors.black.withValues(alpha: 0.6 * t),
              ),
            ),
            if (!draw) const ConfettiOverlay(particleCount: 100),
            Center(
              child: Transform.scale(
                scale: 0.6 + scaleT * 0.4,
                child: Opacity(
                  opacity: t,
                  child: _buildCard(winnerColor, winnerLabel, draw),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard(final Color winnerColor, final String winnerLabel, final bool draw) {
    final Size screen = MediaQuery.of(context).size;
    // Three tiers — kept consistent with [Responsive.isCompact] used by
    // the rest of the app (520 px height threshold). The previous
    // `< 400` cutoff missed every landscape phone (Pixel 6 at 915×412,
    // iPhone SE at 667×375, etc.) and the regular-tier paddings
    // overflowed those screens by ~160 px.
    final bool compact = Responsive.isCompact(context);
    final bool isTablet = !compact && screen.shortestSide >= 600;

    final double maxWidth = isTablet ? 620 : 460;
    final EdgeInsets cardPad = compact
        ? const EdgeInsets.fromLTRB(20, 14, 20, 12)
        : isTablet
            ? const EdgeInsets.fromLTRB(40, 44, 40, 32)
            : const EdgeInsets.fromLTRB(28, 32, 28, 24);

    final double trophySize = compact ? 48 : (isTablet ? 128 : 96);
    final double fullTimeFont = compact ? 12 : (isTablet ? 26 : 20);
    final double winnerFont = compact ? 24 : (isTablet ? 60 : 44);
    final double gapAfterTrophy = compact ? 4 : (isTablet ? 18 : 14);
    final double gapAfterFullTime = compact ? 2 : (isTablet ? 6 : 4);
    final double gapBeforeScore = compact ? 8 : (isTablet ? 30 : 24);
    final double gapBeforePlay = compact ? 10 : (isTablet ? 36 : 28);
    final double gapBeforeHome = compact ? 2 : (isTablet ? 14 : 10);

    // The card itself never exceeds the screen height — wrap its
    // contents in a SingleChildScrollView as a belt-and-braces guard
    // against any future small-device edge case (e.g. split-screen,
    // foldable in flex mode, accessibility text scale > 1.0). With the
    // tighter compact tier above the scroll bar should never appear in
    // practice.
    final double maxCardHeight = screen.height - 24;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxCardHeight),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: cardPad,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFF101F10),
            Color.lerp(const Color(0xFF101F10), winnerColor, 0.18)!,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: winnerColor.withValues(alpha: 0.7), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: winnerColor.withValues(alpha: 0.55),
            blurRadius: 60,
            spreadRadius: 4,
          ),
          const BoxShadow(
            color: Colors.black87,
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _AnimatedTrophy(
              controller: _trophyShine,
              color: winnerColor,
              draw: draw,
              size: trophySize,
            ),
            SizedBox(height: gapAfterTrophy),
            Text(
              'FULL TIME',
              style: AppFonts.bebasNeue(
                fontSize: fullTimeFont,
                letterSpacing: 6,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            SizedBox(height: gapAfterFullTime),
            ShaderMask(
              shaderCallback: (final Rect bounds) {
                return LinearGradient(
                  colors: <Color>[
                    AppColors.goldDeep,
                    AppColors.goldShine,
                    AppColors.goldDeep,
                  ],
                ).createShader(bounds);
              },
              child: Text(
                winnerLabel,
                style: AppFonts.bebasNeue(
                  fontSize: winnerFont,
                  letterSpacing: 3,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(color: winnerColor.withValues(alpha: 0.7), blurRadius: 24),
                  ],
                ),
              ),
            ),
            SizedBox(height: gapBeforeScore),
            _ScoreRow(
              redScore: widget.redScore,
              blueScore: widget.blueScore,
              compact: compact,
              isTablet: isTablet,
            ),
            SizedBox(height: gapBeforePlay),
            _PlayAgainButton(
              onTap: () {
                AudioHelper.select();
                widget.onPlayAgain();
              },
              compact: compact,
              isTablet: isTablet,
            ),
            SizedBox(height: gapBeforeHome),
            TextButton.icon(
              onPressed: () {
                AudioHelper.select();
                widget.onHome();
              },
              icon: Icon(
                Icons.home_rounded,
                color: Colors.white70,
                size: isTablet ? 24 : 18,
              ),
              label: Text(
                'HOME',
                style: TextStyle(
                  color: Colors.white70,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  fontSize: isTablet ? 16 : 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedTrophy extends StatelessWidget {
  const _AnimatedTrophy({
    required this.controller,
    required this.color,
    required this.draw,
    this.size = 96,
  });

  final AnimationController controller;
  final Color color;
  final bool draw;
  final double size;

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (final BuildContext context, final Widget? child) {
        final double t = controller.value;
        final double bob = sin(t * pi * 2) * 4;
        return Transform.translate(
          offset: Offset(0, bob),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  AppColors.goldShine,
                  AppColors.goldBright,
                  AppColors.goldDeep,
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.goldBright.withValues(
                    alpha: 0.7 + sin(t * pi * 4) * 0.25,
                  ),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Text(
                draw ? '🤝' : '🏆',
                style: TextStyle(fontSize: size * 0.52),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.redScore,
    required this.blueScore,
    this.compact = false,
    this.isTablet = false,
  });
  final int redScore;
  final int blueScore;
  final bool compact;
  final bool isTablet;

  @override
  Widget build(final BuildContext context) {
    final EdgeInsets pad = compact
        ? const EdgeInsets.symmetric(vertical: 10, horizontal: 12)
        : isTablet
            ? const EdgeInsets.symmetric(vertical: 24, horizontal: 24)
            : const EdgeInsets.symmetric(vertical: 18, horizontal: 16);
    final double dashFont = compact ? 32 : (isTablet ? 76 : 56);
    final double dashHorizPad = compact ? 8 : (isTablet ? 24 : 16);
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _scoreSide(
            label: TeamColors.name(Team.red),
            score: redScore,
            color: TeamColors.redLight(),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dashHorizPad),
            child: Text(
              '–',
              style: AppFonts.bebasNeue(
                color: Colors.white54,
                fontSize: dashFont,
                height: 0.9,
              ),
            ),
          ),
          _scoreSide(
            label: TeamColors.name(Team.blue),
            score: blueScore,
            color: TeamColors.blueLight(),
          ),
        ],
      ),
    );
  }

  Widget _scoreSide({
    required final String label,
    required final int score,
    required final Color color,
  }) {
    final double labelFont = compact ? 10 : (isTablet ? 16 : 12);
    final double scoreFont = compact ? 36 : (isTablet ? 84 : 64);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: labelFont,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: compact ? 2 : 4),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: score),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (final BuildContext context, final int value, final Widget? child) {
            return Text(
              '$value',
              style: AppFonts.bebasNeue(
                color: color,
                fontSize: scoreFont,
                height: 0.95,
                shadows: <Shadow>[
                  Shadow(color: color.withValues(alpha: 0.6), blurRadius: 20),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PlayAgainButton extends StatefulWidget {
  const _PlayAgainButton({
    required this.onTap,
    this.compact = false,
    this.isTablet = false,
  });
  final VoidCallback onTap;
  final bool compact;
  final bool isTablet;

  @override
  State<_PlayAgainButton> createState() => _PlayAgainButtonState();
}

class _PlayAgainButtonState extends State<_PlayAgainButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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
        return AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
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
              padding: EdgeInsets.symmetric(
                vertical: widget.compact
                    ? 11
                    : widget.isTablet
                        ? 22
                        : 18,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    AppColors.goldBright,
                    Color(0xFFFF9800),
                  ],
                ),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.goldBright.withValues(alpha: 0.6 + t * 0.4),
                    blurRadius: 18 + t * 18,
                    spreadRadius: 1 + t * 4,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.refresh_rounded,
                    size: widget.compact
                        ? 18
                        : widget.isTablet
                            ? 32
                            : 26,
                    color: const Color(0xFF1B1B1B),
                  ),
                  SizedBox(width: widget.compact ? 6 : 10),
                  Text(
                    'PLAY AGAIN',
                    style: AppFonts.bebasNeue(
                      fontSize: widget.compact
                          ? 18
                          : widget.isTablet
                              ? 32
                              : 26,
                      letterSpacing: 4,
                      color: const Color(0xFF1B1B1B),
                      fontWeight: FontWeight.w800,
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

class GameOverHost extends StatelessWidget {
  const GameOverHost({super.key});

  @override
  Widget build(final BuildContext context) {
    return BlocBuilder<GameBloc, GameState>(
      buildWhen: (final GameState p, final GameState n) =>
          p.phase != n.phase || p.redScore != n.redScore || p.blueScore != n.blueScore,
      builder: (final BuildContext context, final GameState state) {
        if (state.phase != GamePhase.gameOver) return const SizedBox.shrink();
        return GameOverWidget(
          redScore: state.redScore,
          blueScore: state.blueScore,
          onPlayAgain: () async {
            // Post-match interstitial before resetting → coin toss.
            // Gated remotely by `show_ads` + `show_interstitial_on_play_again`.
            final GameBloc bloc = context.read<GameBloc>();
            await AdManager.instance.showPlayAgainInterstitial();
            bloc.add(const ResetGameEvent());
          },
          onHome: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        );
      },
    );
  }
}

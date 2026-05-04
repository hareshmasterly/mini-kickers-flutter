import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/team_colors.dart';
import 'package:mini_kickers/utils/ad_manager.dart';
import 'package:mini_kickers/utils/analytics_helper.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/responsive.dart';
import 'package:mini_kickers/views/game/widget/board_widget.dart';
import 'package:mini_kickers/views/game/widget/coin_toss_widget.dart';
import 'package:mini_kickers/views/game/widget/commentary_toast.dart';
import 'package:mini_kickers/views/game/widget/first_goal_ad_overlay.dart';
import 'package:mini_kickers/views/game/widget/game_over_widget.dart';
import 'package:mini_kickers/views/game/widget/goal_flash_widget.dart';
import 'package:mini_kickers/views/game/widget/move_debug_overlay.dart';
import 'package:mini_kickers/views/game/widget/restart_confirm_dialog.dart';
import 'package:mini_kickers/views/game/widget/screen_shake.dart';
import 'package:mini_kickers/views/game/widget/team_side_panel.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final ShakeController _shakeController = ShakeController();

  /// True while the promo overlay is visible. Cleared when the user
  /// dismisses the card or when a new match starts.
  bool _showGoalAd = false;

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // The team-setup dialog (opened from the coin-toss strip) is the
      // only thing on this screen that summons a keyboard, and it lives
      // in the Overlay above the Scaffold and handles its own keyboard
      // accommodation. Letting the body resize would unnecessarily
      // squeeze the coin-toss card / game board behind the dialog.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          const _AmbientBackground(),
          BlocConsumer<GameBloc, GameState>(
            listenWhen: (final GameState p, final GameState n) =>
                // Trigger on goal start (for shake), on goal-flash end
                // (to pop the promo right after the celebration), and on
                // any return to the coin-toss phase (close any open card).
                (!p.showGoalFlash && n.showGoalFlash) ||
                    (p.showGoalFlash && !n.showGoalFlash) ||
                    (p.phase != GamePhase.coinToss &&
                        n.phase == GamePhase.coinToss),
            listener: (final BuildContext context, final GameState state) {
              // New match started — close any lingering promo card.
              if (state.phase == GamePhase.coinToss) {
                if (_showGoalAd) {
                  setState(() => _showGoalAd = false);
                }
                return;
              }
              if (state.showGoalFlash) {
                _shakeController.shake();
                return;
              }
              // Goal flash just ended.
              //   • Nth goal (when goal slot enabled) → paid interstitial
              //   • Otherwise (and Amazon overlay enabled) → house promo
              //   • Otherwise still → no overlay at all
              // Cadence + toggles come from remote `app_settings`; see
              // [AdManager.shouldShowGoalInterstitial] and
              // [SettingsService.showAmazonAdOverlay].
              if (AdManager.instance.shouldShowGoalInterstitial()) {
                AdManager.instance.showGoalInterstitial();
              } else if (SettingsService.instance.showAmazonAdOverlay &&
                  !_showGoalAd) {
                setState(() => _showGoalAd = true);
              }
            },
            builder: (final BuildContext context, final GameState state) {
              return Stack(
                children: <Widget>[
                  SafeArea(
                    child: ScreenShake(
                      controller: _shakeController,
                      child: _buildContent(context),
                    ),
                  ),
                  if (state.showGoalFlash) const GoalFlashWidget(),
                  const GameOverHost(),
                  const CoinTossHost(),
                  // Commentary toast — anchored to the screen's top-right
                  // corner (NOT the board) so it never overlaps tokens or
                  // the ball when they're in the bottom rows. The toast
                  // handles its own safe-area + positioning internally.
                  const CommentaryToast(),
                  // Debug-only readout (compiled out of release).
                  const MoveDebugOverlay(),
                  if (_showGoalAd)
                    FirstGoalAdOverlay(
                      onDismiss: () {
                        if (!mounted) return;
                        setState(() => _showGoalAd = false);
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(final BuildContext context) {
    // Single-source breakpoints — see [Responsive] for the cutoff values.
    final bool compact = Responsive.isCompact(context);
    return Padding(
      padding: EdgeInsets.all(compact ? 10 : 16),
      child: Column(
        children: <Widget>[
          _TopBar(
            compact: compact,
            onExit: () => _handleExit(context),
          ),
          SizedBox(height: compact ? 8 : 14),
          Expanded(child: _wideLayout(compact: compact)),
        ],
      ),
    );
  }

  Future<void> _handleExit(final BuildContext context) async {
    final GameBloc bloc = context.read<GameBloc>();
    final bool gameInProgress =
        bloc.state.phase != GamePhase.coinToss &&
            bloc.state.phase != GamePhase.gameOver &&
            (bloc.state.redScore > 0 ||
                bloc.state.blueScore > 0 ||
                bloc.state.timeLeft < GameConfig.matchSeconds);

    if (!gameInProgress) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (final BuildContext ctx) => const _ExitConfirmDialog(),
    );

    if (confirmed == true && context.mounted) {
      // Pop first so the toss screen never flashes during the transition,
      // THEN reset the bloc once we're back on the home screen.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        bloc.add(const ResetGameEvent());
      });
    }
  }

  Widget _wideLayout({required final bool compact}) {
    // Each player has their own panel + dice on their physical side of
    // the device — no more reaching across to roll.
    //
    // BOTH panels are wrapped in RotatedBox so they FACE THEIR PLAYER:
    //   • Left  panel → quarterTurns: 1 (90° CW)  — content's
    //     reading-direction "top" ends up at screen-right (= player 1's
    //     "up" direction when sitting on the device's left side and
    //     looking inward).
    //   • Right panel → quarterTurns: 3 (90° CCW) — mirror of the above
    //     for player 2 sitting on the device's right side.
    //
    // The panel itself is laid out HORIZONTALLY internally (a row of
    // [team strip] [score] [LIVE pip] [dice + caption]). After rotation
    // it appears as a vertical strip at the screen edge, with each
    // section running top→bottom from that player's viewpoint.
    final bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    // Tablet panel width: trimmed in steps from 170 → 130 → 110 for a
    // slimmer, more board-focused look on iPad. At 110 the panel is
    // only marginally wider than the phone tier (118), which is the
    // right tradeoff — even on a 12.9" display the dice + score stay
    // perfectly readable across the table while the board gets the
    // overwhelming majority of the screen.
    final double panelWidth = compact ? 84 : (isTablet ? 110 : 118);
    final double gap = compact ? 8 : 14;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: panelWidth,
          child: const RotatedBox(
            quarterTurns: 1,
            child: TeamSidePanel(team: Team.red),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            children: <Widget>[
              const Expanded(child: BoardWidget()),
              const SizedBox(height: 10),
              _LegendBar(compact: compact),
            ],
          ),
        ),
        SizedBox(width: gap),
        SizedBox(
          width: panelWidth,
          child: const RotatedBox(
            quarterTurns: 3,
            child: TeamSidePanel(team: Team.blue),
          ),
        ),
      ],
    );
  }
}

/// Top-of-screen bar: Exit (left), live match timer + brand title
/// (centre), Restart (right). Replaces the old vertical _Header — the
/// new 3-column layout (left team panel, board, right team panel)
/// needed every vertical pixel for the panels, and the title was
/// dominating space without adding gameplay info.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.compact, required this.onExit});

  final bool compact;
  final VoidCallback onExit;

  @override
  Widget build(final BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _ExitButton(compact: compact, onConfirmed: onExit),
        const Spacer(),
        BlocBuilder<GameBloc, GameState>(
          buildWhen: (final GameState p, final GameState n) =>
              p.timeLeft != n.timeLeft,
          builder: (final BuildContext context, final GameState state) {
            return _TimerCapsule(
              timeLeft: state.timeLeft,
              compact: compact,
            );
          },
        ),
        if (!compact) ...<Widget>[
          const SizedBox(width: 16),
          const _BrandWatermark(),
        ],
        const Spacer(),
        _RestartButton(compact: compact),
      ],
    );
  }
}

/// Glassmorphic capsule showing `M:SS` time-remaining. Pulses + flashes
/// red below 1 minute.
class _TimerCapsule extends StatelessWidget {
  const _TimerCapsule({required this.timeLeft, required this.compact});

  final int timeLeft;
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    final bool low = timeLeft <= 60;
    final String mm = (timeLeft ~/ 60).toString();
    final String ss = (timeLeft % 60).toString().padLeft(2, '0');
    final Color tint = low ? const Color(0xFFFF5555) : AppColors.accent;
    final double fontSize = compact ? 22 : 30;
    final EdgeInsets pad = compact
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 22, vertical: 10);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: low ? 1.06 : 1),
      duration: const Duration(milliseconds: 600),
      builder:
          (final BuildContext context, final double scale, final Widget? child) =>
              Transform.scale(scale: scale, child: child),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: pad,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: tint.withValues(alpha: 0.55),
                width: 1.4,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tint.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.timer_rounded,
                  color: tint,
                  size: compact ? 14 : 18,
                ),
                SizedBox(width: compact ? 6 : 8),
                Text(
                  '$mm:$ss',
                  style: AppFonts.bebasNeue(
                    fontSize: fontSize,
                    color: tint,
                    letterSpacing: 2,
                    shadows: <Shadow>[
                      Shadow(
                        color: tint.withValues(alpha: 0.55),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle "MINI KICKERS" brand mark sitting next to the timer on
/// non-compact screens. Hidden on compact (height < 520) to save
/// vertical real estate for the panels.
class _BrandWatermark extends StatelessWidget {
  const _BrandWatermark();

  @override
  Widget build(final BuildContext context) {
    return ShaderMask(
      shaderCallback: (final Rect bounds) {
        return LinearGradient(
          colors: <Color>[
            AppColors.accent.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.95),
            AppColors.accent.withValues(alpha: 0.85),
          ],
          stops: const <double>[0.0, 0.5, 1.0],
        ).createShader(bounds);
      },
      child: Text(
        'MINI KICKERS',
        style: AppFonts.bebasNeue(
          fontSize: 22,
          letterSpacing: 3,
          color: Colors.white,
          shadows: <Shadow>[
            Shadow(
              color: AppColors.accent.withValues(alpha: 0.45),
              blurRadius: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Glassmorphic restart button on the right of the top bar. Triggers
/// the [RestartConfirmDialog] before doing anything irreversible.
class _RestartButton extends StatelessWidget {
  const _RestartButton({required this.compact});

  final bool compact;

  @override
  Widget build(final BuildContext context) {
    final double iconSize = compact ? 14 : 18;
    final double fontSize = compact ? 10 : 12;
    final EdgeInsets pad = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    return GestureDetector(
      onTap: () async {
        AudioHelper.select();
        final GameBloc bloc = context.read<GameBloc>();
        final bool? confirmed = await showDialog<bool>(
          context: context,
          barrierColor: Colors.black87,
          builder: (final BuildContext ctx) => const RestartConfirmDialog(),
        );
        if (confirmed != true) return;
        Analytics.logGameRestarted();
        // Mid-match restart interstitial — gated remotely, no-op when
        // ads are off or no ad is loaded yet, so the user is never
        // blocked by ad load latency.
        await AdManager.instance.showRestartInterstitial();
        bloc.add(const ResetGameEvent());
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: pad,
            decoration: BoxDecoration(
              color: AppColors.brandYellow.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.brandYellow.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.refresh_rounded,
                  size: iconSize,
                  color: AppColors.brandYellow,
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    'RESTART',
                    style: TextStyle(
                      color: AppColors.brandYellow,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendBar extends StatelessWidget {
  const _LegendBar({required this.compact});
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    final double size = compact ? 10 : 12.5;
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (final BuildContext context, final Widget? child) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  '⬤ ${SettingsService.instance.redName} — ATTACKS RIGHT',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: TeamColors.redLight(),
                    fontSize: size,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${SettingsService.instance.blueName} — ATTACKS LEFT ⬤',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: TeamColors.blueLight(),
                    fontSize: size,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExitButton extends StatelessWidget {
  const _ExitButton({required this.onConfirmed, required this.compact});
  final VoidCallback onConfirmed;
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    final double fontSize = compact ? 10 : 12;
    final double iconSize = compact ? 14 : 18;
    final EdgeInsets pad = compact
        ? const EdgeInsets.symmetric(horizontal: 9, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    return GestureDetector(
      onTap: () {
        AudioHelper.select();
        onConfirmed();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: pad,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: iconSize,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  'EXIT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExitConfirmDialog extends StatelessWidget {
  const _ExitConfirmDialog();

  @override
  Widget build(final BuildContext context) {
    // Tablet only when BOTH dimensions are generous — landscape phones
    // are wide but short, so width-only checks pick the wrong tier.
    final bool isTablet =
        MediaQuery.of(context).size.shortestSide >= 600;
    final double maxWidth = isTablet ? 560 : 400;
    final EdgeInsets cardPad = isTablet
        ? const EdgeInsets.fromLTRB(40, 36, 40, 30)
        : const EdgeInsets.fromLTRB(28, 28, 28, 22);
    final double iconSize = isTablet ? 72 : 50;
    final double titleFont = isTablet ? 44 : 30;
    final double subtitleFont = isTablet ? 16 : 13;
    final double btnVPad = isTablet ? 18 : 14;
    final double keepBtnFont = isTablet ? 15 : 12;
    final double quitBtnFont = isTablet ? 16 : 13;
    final double gapAfterIcon = isTablet ? 14 : 10;
    final double gapAfterTitle = isTablet ? 10 : 6;
    final double gapBeforeButtons = isTablet ? 32 : 22;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
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
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.6), width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.brandRed.withValues(alpha: 0.45),
                blurRadius: 40,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black87,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                size: iconSize,
                color: AppColors.brandYellow,
              ),
              SizedBox(height: gapAfterIcon),
              Text(
                'QUIT MATCH?',
                style: AppFonts.bebasNeue(
                  fontSize: titleFont,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: gapAfterTitle),
              Text(
                'Your current progress will be lost.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: subtitleFont,
                  height: 1.4,
                ),
              ),
              SizedBox(height: gapBeforeButtons),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        AudioHelper.select();
                        Navigator.of(context).pop(false);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        padding: EdgeInsets.symmetric(vertical: btnVPad),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'KEEP PLAYING',
                        style: TextStyle(
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                          fontSize: keepBtnFont,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        AudioHelper.select();
                        Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandRed,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: btnVPad),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 4,
                        shadowColor: AppColors.brandRed,
                      ),
                      child: Text(
                        'QUIT',
                        style: TextStyle(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                          fontSize: quitBtnFont,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmbientBackground extends StatefulWidget {
  const _AmbientBackground();

  @override
  State<_AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<_AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (final BuildContext context, final Widget? child) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(_ctrl.value * 1.2 - 0.6, -0.2),
              radius: 1.6,
              colors: const <Color>[
                Color(0xFF1A2D1A),
                AppColors.bg,
              ],
            ),
          ),
        );
      },
    );
  }
}

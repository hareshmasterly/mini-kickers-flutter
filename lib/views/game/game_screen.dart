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
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/responsive.dart';
import 'package:mini_kickers/views/game/widget/board_widget.dart';
import 'package:mini_kickers/views/game/widget/coin_toss_widget.dart';
import 'package:mini_kickers/views/game/widget/first_goal_ad_overlay.dart';
import 'package:mini_kickers/views/game/widget/game_over_widget.dart';
import 'package:mini_kickers/views/game/widget/goal_flash_widget.dart';
import 'package:mini_kickers/views/game/widget/move_debug_overlay.dart';
import 'package:mini_kickers/views/game/widget/screen_shake.dart';
import 'package:mini_kickers/views/game/widget/side_panel_widget.dart';

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
              //   • Otherwise                         → Amazon promo overlay
              // Cadence + toggles come from remote `app_settings`; see
              // [AdManager.shouldShowGoalInterstitial].
              if (AdManager.instance.shouldShowGoalInterstitial()) {
                AdManager.instance.showGoalInterstitial();
              } else if (!_showGoalAd) {
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
    // App is locked to landscape (see main.dart). The side-by-side
    // (board left, side panel right) layout is always the right call —
    // the stacked narrow layout doesn't fit on small landscape phones
    // (e.g. iPhone SE in landscape, h ~375 dp), where the board would
    // be squashed to nothing.
    return Padding(
      padding: EdgeInsets.all(compact ? 10 : 16),
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              _Header(compact: compact),
              SizedBox(height: compact ? 8 : 16),
              Expanded(child: _wideLayout(compact: compact)),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            child: _ExitButton(
              compact: compact,
              onConfirmed: () => _handleExit(context),
            ),
          ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Column(
            children: <Widget>[
              const Expanded(child: BoardWidget()),
              const SizedBox(height: 10),
              _LegendBar(compact: compact),
            ],
          ),
        ),
        const SizedBox(width: 20),
        const SidePanelWidget(),
      ],
    );
  }

}

class _Header extends StatelessWidget {
  const _Header({required this.compact});
  final bool compact;

  @override
  Widget build(final BuildContext context) {
    final double titleSize = compact ? 30 : 48;
    final double subSize = compact ? 10 : 12;
    return Column(
      children: <Widget>[
        ShaderMask(
          shaderCallback: (final Rect bounds) {
            return const LinearGradient(
              colors: <Color>[
                AppColors.accent,
                Color(0xFFFFFFFF),
                AppColors.accent,
              ],
              stops: <double>[0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: Text(
            'MINI KICKERS',
            style: AppFonts.bebasNeue(
              fontSize: titleSize,
              letterSpacing: titleSize * 0.1,
              color: Colors.white,
              shadows: <Shadow>[
                Shadow(
                  color: AppColors.accent.withValues(alpha: 0.5),
                  blurRadius: compact ? 22 : 40,
                ),
              ],
            ),
          ),
        ),
        Text(
          'ROLL · MOVE · SCORE',
          style: TextStyle(
            color: AppColors.muted,
            letterSpacing: compact ? 2.4 : 3,
            fontSize: subSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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

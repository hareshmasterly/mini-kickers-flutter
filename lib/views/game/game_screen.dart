import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/ai/ai_controller.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/models/match_player.dart';
import 'package:mini_kickers/data/services/match_service.dart';
import 'package:mini_kickers/data/services/online_game_controller.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/data/services/user_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/team_colors.dart';
import 'package:mini_kickers/utils/ad_manager.dart';
import 'package:mini_kickers/utils/analytics_helper.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/handle_generator.dart';
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
import 'package:mini_kickers/views/online/widget/opponent_status_overlay.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.onlineMatchId});

  /// Non-null when this screen was launched from the online lobby.
  /// In that case we instantiate an [OnlineGameController] in
  /// [initState] which subscribes to the `matches/{matchId}` doc and
  /// drives all state sync. Null = local play (vsHuman / vsAi),
  /// preserving every existing call site.
  final String? onlineMatchId;

  /// Convenience: true when this game session is an online 1v1.
  /// Used for ergonomic checks throughout the screen.
  bool get isOnline => onlineMatchId != null;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final ShakeController _shakeController = ShakeController();

  /// True while the promo overlay is visible. Cleared when the user
  /// dismisses the card or when a new match starts.
  bool _showGoalAd = false;

  /// AI driver. Non-null only when [SettingsService.gameMode] is
  /// `vsAi` at screen-mount time AND we're NOT in an online match.
  /// Disposed in [dispose] so we don't leak a bloc subscription if
  /// the user backs out mid-match.
  AiController? _aiController;

  /// Online-1v1 driver. Non-null only when [GameScreen.onlineMatchId]
  /// is non-null. Owns the Firestore subscription, the bloc push hook
  /// and the heartbeat polling. Disposed before pop so the queue +
  /// connection docs are cleaned up.
  OnlineGameController? _onlineController;

  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so `context.read<GameBloc>()`
    // has a fully resolved provider tree above us.
    WidgetsBinding.instance.addPostFrameCallback((final _) async {
      if (!mounted) return;
      if (widget.isOnline) {
        await _startOnline();
      } else if (SettingsService.instance.gameMode == GameMode.vsAi) {
        _aiController = AiController(bloc: context.read<GameBloc>());
        _aiController!.start();
      }
    });
  }

  Future<void> _startOnline() async {
    final GameBloc bloc = context.read<GameBloc>();
    final OnlineGameController controller = OnlineGameController(
      bloc: bloc,
      matchId: widget.onlineMatchId!,
    );
    _onlineController = controller;
    // Pre-emptively flip the game-mode setting for the duration of
    // this match so any settings-driven UI (e.g. the team-setup strip
    // in coin toss) reflects "online" semantics.
    SettingsService.instance.gameMode = GameMode.vsOnline;
    // start() awaits the first inbound sync (~1 RTT) so the bloc has
    // a populated state before the user can act. Errors are surfaced
    // via the controller's events stream → OpponentStatusOverlay.
    await controller.start();
  }

  @override
  void dispose() {
    _aiController?.dispose();
    // Tear down the online controller synchronously — its dispose is
    // async but we don't await (Widget.dispose is sync). The call
    // queues unsubscribe + heartbeat-stop work that completes shortly
    // after the widget is gone; safe because we set flags inside the
    // controller before any async work.
    _onlineController?.dispose();
    super.dispose();
  }

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
              final GameBloc bloc = context.read<GameBloc>();
              // New match started — close any lingering promo card AND
              // make sure the AI / match timer aren't left paused from
              // a previous goal.
              if (state.phase == GamePhase.coinToss) {
                if (_showGoalAd) {
                  setState(() => _showGoalAd = false);
                }
                _aiController?.resume();
                bloc.resumeTimer();
                return;
              }
              if (state.showGoalFlash) {
                _shakeController.shake();
                // Pause AI AND match timer the moment the goal flash
                // starts. Two separate concerns:
                //   • AI must not act behind an ad overlay.
                //   • Match clock must not lose seconds while the user
                //     is looking at an ad they didn't ask for.
                // Resumed in the appropriate branch below once the
                // overlay (if any) is dismissed.
                _aiController?.pause();
                bloc.pauseTimer();
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
                // Already paused above (AI + timer). Resume both once
                // the interstitial dismisses.
                AdManager.instance.showGoalInterstitial().then((final _) {
                  if (!mounted) return;
                  _aiController?.resume();
                  bloc.resumeTimer();
                });
              } else if (SettingsService.instance.showAmazonAdOverlay &&
                  !_showGoalAd) {
                // Already paused. AI + timer resume inside the
                // FirstGoalAdOverlay onDismiss callback below.
                setState(() => _showGoalAd = true);
              } else {
                // No overlay → resume immediately so neither stays
                // stuck paused for the rest of the match.
                _aiController?.resume();
                bloc.resumeTimer();
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
                        // Overlay gone → safe for the AI to resume its
                        // turn AND for the match clock to start
                        // counting again.
                        _aiController?.resume();
                        context.read<GameBloc>().resumeTimer();
                      },
                    ),
                  // Online-only: disconnect / forfeit / sync-error
                  // overlays. Driven by OnlineGameController.events.
                  // Renders nothing in local play.
                  if (_onlineController != null && state.online != null)
                    OpponentStatusOverlay(
                      controller: _onlineController!,
                      opponent: state.online!.opponent,
                      forfeitCountdown: const Duration(seconds: 30),
                      onForfeitConfirmed: _handleOpponentForfeited,
                      onSyncErrorAck: _handleSyncError,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Called by [OpponentStatusOverlay] when the forfeit countdown
  /// expires (the controller already wrote `status: forfeited` to the
  /// match doc — this just handles the local UI follow-up).
  void _handleOpponentForfeited() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opponent left — match recorded as a win!'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
    Analytics.logOnlineForfeit();
  }

  /// Called by [OpponentStatusOverlay] when the user taps "GO HOME"
  /// after a hard sync error (Firestore unreachable, doc missing).
  void _handleSyncError() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
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
            isOnline: widget.isOnline,
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

    // Online: ALWAYS confirm before leaving — even before kickoff.
    // Leaving forfeits the match (the opponent's controller will mark
    // us as the forfeiter via heartbeat timeout, but we also do it
    // explicitly here so they see "opponent left" within seconds
    // instead of having to wait the full 60s window).
    final bool isOnlineMatch = widget.isOnline && bloc.state.online != null;
    if (!gameInProgress && !isOnlineMatch) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (final BuildContext ctx) =>
          _ExitConfirmDialog(isOnline: isOnlineMatch),
    );

    if (confirmed == true && context.mounted) {
      if (isOnlineMatch) {
        // Stamp the match doc as forfeited by us. Fire-and-forget —
        // even if the write fails, the opponent's heartbeat-poller
        // will eventually mark us out.
        final String? selfUid = UserService.instance.uid;
        if (selfUid != null) {
          MatchService.instance
              .markMatchForfeited(
                bloc.state.online!.matchId,
                forfeitedByUid: selfUid,
              )
              .catchError((final _) {});
        }
        Analytics.logOnlineForfeit();
      }
      // Pop first so the toss screen never flashes during the transition,
      // THEN reset the bloc once we're back on the home screen.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        // Reset back to local mode so the next match the user starts
        // doesn't accidentally inherit the online context.
        SettingsService.instance.gameMode = GameMode.vsHuman;
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
///
/// Online mode swaps two pieces:
///   • The brand watermark next to the timer becomes an opponent
///     chip ("VS handle") so the user always knows who they're
///     playing.
///   • The Restart button is hidden — restarting in the middle of an
///     online match would desync state. Players can only Exit
///     (which forfeits) or finish naturally.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.compact,
    required this.onExit,
    this.isOnline = false,
  });

  final bool compact;
  final VoidCallback onExit;
  final bool isOnline;

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
          if (isOnline)
            const _OpponentChip()
          else
            const _BrandWatermark(),
        ],
        const Spacer(),
        // Restart is meaningless in online play (would desync the
        // opponent). We replace it with an invisible spacer the same
        // size so the timer + opponent chip stay centred.
        if (isOnline)
          SizedBox(width: compact ? 32 : 110)
        else
          _RestartButton(compact: compact),
      ],
    );
  }
}

/// Online-only top-bar chip showing "VS \[emoji\] \[handle\]". Reads the
/// opponent identity from the bloc's [OnlineContext] so it stays in
/// sync with the live match doc (handle changes mid-match are rare,
/// but the chip would still pick them up).
class _OpponentChip extends StatelessWidget {
  const _OpponentChip();

  @override
  Widget build(final BuildContext context) {
    return BlocBuilder<GameBloc, GameState>(
      buildWhen: (final GameState p, final GameState n) =>
          p.online?.opponent.uid != n.online?.opponent.uid ||
          p.online?.opponent.displayName != n.online?.opponent.displayName,
      builder: (final BuildContext context, final GameState state) {
        final MatchPlayer? opp = state.online?.opponent;
        if (opp == null) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.brandYellow.withValues(alpha: 0.5),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'VS',
                    style: AppFonts.bebasNeue(
                      fontSize: 14,
                      letterSpacing: 2,
                      color: AppColors.brandYellow,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    HandleGenerator.emojiFor(opp.avatarId),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      opp.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
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
                  '⬤ ${TeamColors.name(Team.red)} — ATTACKS RIGHT',
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
                  '${TeamColors.name(Team.blue)} — ATTACKS LEFT ⬤',
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
  const _ExitConfirmDialog({this.isOnline = false});

  /// True when the user is leaving an in-progress online match —
  /// changes the warning copy from "your progress will be lost" to
  /// "this counts as a forfeit". Stat-bumping for forfeits lives in
  /// the controller; this dialog just sets expectations honestly.
  final bool isOnline;

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
                isOnline ? 'FORFEIT MATCH?' : 'QUIT MATCH?',
                style: AppFonts.bebasNeue(
                  fontSize: titleFont,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: gapAfterTitle),
              Text(
                isOnline
                    ? "Leaving now counts as a forfeit and your\n"
                        "opponent wins by default."
                    : 'Your current progress will be lost.',
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

import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/models/ai_difficulty_option.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/routes/routes_name.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/data/services/app_update_service.dart';
import 'package:mini_kickers/data/services/user_service.dart';
import 'package:mini_kickers/utils/analytics_helper.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/responsive.dart';
import 'package:mini_kickers/views/home/widget/update_dialog.dart';
import 'package:mini_kickers/views/game/game_screen.dart';
import 'package:mini_kickers/views/home/widget/animated_title.dart';
import 'package:mini_kickers/views/home/widget/buy_amazon_button.dart';
import 'package:mini_kickers/views/home/widget/difficulty_picker_dialog.dart';
import 'package:mini_kickers/views/home/widget/glass_action_card.dart';
import 'package:mini_kickers/views/home/widget/hero_showcase.dart';
import 'package:mini_kickers/views/home/widget/mode_card.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';
import 'package:mini_kickers/views/home/widget/welcome_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    // Start background music if enabled in settings
    WidgetsBinding.instance.addPostFrameCallback((final _) {
      if (SettingsService.instance.musicEnabled) {
        AudioHelper.startMusic();
      }
    });

    // Analytics — fires once per home-screen mount (returning to home
    // from a game also re-fires, which is what we want for measuring
    // session-level engagement).
    Analytics.logHomeOpened();

    // Check for an app-update prompt. Done after a brief delay so the
    // home screen has time to render its entry animation before the
    // dialog covers it. The check is best-effort and silently no-ops
    // on any failure (network down, doc missing, etc.) so it can
    // never block the user from playing.
    //
    // The welcome card (first-launch only) takes priority — we run
    // it FIRST and await dismissal. Update check follows so the
    // user always sees the welcome BEFORE any update prompt.
    WidgetsBinding.instance.addPostFrameCallback((final _) async {
      // 1. First-launch welcome card — only shown when the user has
      //    no saved profile yet. After confirmation it never appears
      //    again on this install.
      if (UserService.instance.isFirstLaunch && mounted) {
        await showWelcomeCard(context);
      }
      if (!mounted) return;

      // 2. Update check.
      Future<void>.delayed(const Duration(milliseconds: 400), () async {
        if (!mounted) return;
        final UpdateCheckResult result =
            await AppUpdateService.instance.check();
        if (!mounted || !result.shouldShow) return;
        await showUpdateDialog(context, result: result);
      });
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _onPlay() {
    Analytics.logGameStarted();
    // Default "PLAY" entry point — local two-player. Make sure mode is
    // reset to vsHuman in case the user previously played a VS AI match
    // and bailed without going through the AI flow's cleanup.
    SettingsService.instance.gameMode = GameMode.vsHuman;
    _startGame();
  }

  /// Opens the difficulty picker, then starts a VS AI match if the
  /// user confirmed. The picker is shown on every "VS AI" tap by
  /// design (see decision §2 in [docs/vs_ai_feature_spec.md]).
  Future<void> _onPlayVsAi() async {
    AudioHelper.select();
    final AiDifficulty? picked = await showDifficultyPickerDialog(context);
    if (picked == null) return;
    if (!mounted) return;
    SettingsService.instance.gameMode = GameMode.vsAi;
    _startGame();
  }

  void _startGame() {
    // Always start fresh: reset bloc so a new coin toss + new timer apply
    context.read<GameBloc>().add(const ResetGameEvent());
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        reverseTransitionDuration: const Duration(milliseconds: 500),
        settings: const RouteSettings(name: RouteName.gameScreen),
        pageBuilder: (
          final BuildContext context,
          final Animation<double> a,
          final Animation<double> b,
        ) =>
            const GameScreen(),
        transitionsBuilder: (
          final BuildContext context,
          final Animation<double> a,
          final Animation<double> b,
          final Widget child,
        ) {
          final Animation<double> curved =
              CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.18, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    ).then((final _) {
      // After returning from the game screen, snap mode back to vsHuman
      // so the next default-PLAY tap doesn't accidentally launch VS AI.
      if (!mounted) return;
      SettingsService.instance.gameMode = GameMode.vsHuman;
    });
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.stadiumDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const StadiumBackground(),
          SafeArea(
            child: AnimatedBuilder(
              animation: _entry,
              builder: (final BuildContext context, final Widget? child) {
                return _buildContent(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  double _e(final double from, final double to) {
    final double v = ((_entry.value - from) / (to - from)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(v);
  }

  Widget _buildContent(final BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          _buildTopBar(context),
          const SizedBox(height: 8),
          // Same vertical layout on phone and tablet — only the sizing
          // tiers shift. Avoids a totally different visual flow between
          // form factors.
          Expanded(child: _unifiedLayout(context, size)),
          const SizedBox(height: 8),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildTopBar(final BuildContext context) {
    final double t = _e(0.0, 0.4);
    final bool compact = Responsive.isShort(context);
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, -10 * (1 - t)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _CircleIconButton(
              icon: SettingsService.instance.soundEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              onTap: () {
                final bool newValue =
                    !SettingsService.instance.soundEnabled;
                SettingsService.instance.setSoundEnabled(newValue);
                if (newValue) AudioHelper.select();
                setState(() {});
              },
            ),
            BuyAmazonButton(compact: compact),
            _CircleIconButton(
              icon: Icons.settings_rounded,
              onTap: () async {
                AudioHelper.select();
                final GameBloc bloc = context.read<GameBloc>();
                await Navigator.of(context)
                    .pushNamed(RouteName.settingsScreen);
                if (!mounted) return;
                // Apply any setting changes (match duration, music, etc.) live
                bloc.add(const RefreshSettingsEvent());
                if (SettingsService.instance.musicEnabled) {
                  AudioHelper.startMusic();
                } else {
                  AudioHelper.stopMusic();
                }
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Single side-by-side layout — hero on the left, controls on the
  /// right — used on every screen size: phone, tablet, and iPad. Same
  /// structure everywhere; only the sizing tiers shift.
  ///
  /// Sizing rules:
  ///   • Compact / short (h < 460) — landscape phones, slim everything.
  ///   • Regular (h ≥ 460, e.g. iPad / tablet) — the original full-size
  ///     hero layout. **Tablets are NOT compacted** — only mobile is.
  Widget _unifiedLayout(final BuildContext context, final Size size) {
    final double t1 = _e(0.1, 0.7);
    final double t2 = _e(0.25, 0.85);
    final double t3 = _e(0.4, 0.95);
    final double t4 = _e(0.55, 1.0);
    return LayoutBuilder(
      builder: (final BuildContext ctx, final BoxConstraints cons) {
        final double h = cons.maxHeight;
        final bool ultraShort = h < 320;
        final bool short = h < 460;
        final bool compact = short;
        final bool isTablet = size.width >= 720;

        // Title font tiers. iPad gets a much bigger title to fill its
        // generous landscape canvas — small 78 looks cramped there.
        final double titleFont = ultraShort
            ? 24
            : short
                ? 32
                : isTablet
                    ? 96
                    : (size.width < 360 ? 38 : 52);
        // The two-card mode row replaces the previous single PLAY
        // button. Width scales the same way the old playButtonWidth
        // did so the right-column composition stays balanced.
        final double modesRowWidth = ultraShort
            ? 280
            : short
                ? 340
                : isTablet
                    ? 540
                    : 420;
        final double modesGap = ultraShort
            ? 8
            : short
                ? 10
                : isTablet
                    ? 18
                    : 14;
        // Larger gaps on iPad — the content fills more vertical space
        // and stops feeling like a small island in a big screen.
        final double gapAfterTitle = ultraShort
            ? 8
            : short
                ? 14
                : isTablet
                    ? 48
                    : 30;
        final double gapAfterButton = ultraShort
            ? 8
            : short
                ? 12
                : isTablet
                    ? 38
                    : 24;
        final double midGap = ultraShort
            ? 12
            : short
                ? 16
                : isTablet
                    ? 36
                    : 24;

        return Row(
          children: <Widget>[
            // ── Left: hero (auto-fits its column) ──
            Expanded(
              flex: 5,
              child: LayoutBuilder(
                builder: (
                  final BuildContext heroCtx,
                  final BoxConstraints heroCons,
                ) {
                  final double maxByW = heroCons.maxWidth / 2.4;
                  final double maxByH = heroCons.maxHeight / 2.04;
                  // Cap at 180 to match the original tablet hero size
                  // — bigger looks bloated on iPad's portrait flex slot.
                  final double diceSize =
                      min(maxByW, maxByH).clamp(60.0, 180.0);
                  return Center(
                    child: Opacity(
                      opacity: t2,
                      child: Transform.scale(
                        scale: 0.85 + t2 * 0.15,
                        child: HeroShowcase(diceSize: diceSize),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(width: midGap),
            // ── Right: title + play + action row ──
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Opacity(
                    opacity: t1,
                    child: Transform.translate(
                      offset: Offset(30 * (1 - t1), 0),
                      child: AnimatedTitle(fontSize: titleFont),
                    ),
                  ),
                  SizedBox(height: gapAfterTitle),
                  Opacity(
                    opacity: t3,
                    child: Transform.translate(
                      offset: Offset(0, 30 * (1 - t3)),
                      child: _buildModesRow(
                        width: modesRowWidth,
                        gap: modesGap,
                        compact: compact,
                        ultraShort: ultraShort,
                        isTablet: isTablet,
                      ),
                    ),
                  ),
                  SizedBox(height: gapAfterButton),
                  Opacity(
                    opacity: t4,
                    child: _buildActionRow(compact: compact),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Two-card primary mode selector — the visual centrepiece of the
  /// home screen. Wrapped in a [ListenableBuilder] so the AI card's
  /// difficulty chip stays in sync when the user picks a new tier in
  /// the picker (or in Settings).
  Widget _buildModesRow({
    required final double width,
    required final double gap,
    required final bool compact,
    required final bool ultraShort,
    required final bool isTablet,
  }) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (final BuildContext context, final Widget? _) {
        final SettingsService s = SettingsService.instance;

        // Use the Firestore-driven display name for the chip
        // (e.g. "BEGINNER" / "PRO" / "CHAMPION") rather than the raw
        // enum id ("EASY"/...). Falls back to the enum id if the
        // current difficulty isn't found in the available list.
        final List<AiDifficultyOption> options = s.availableAiDifficulties;
        final AiDifficultyOption aiOption = options.firstWhere(
          (final AiDifficultyOption o) => o.id == s.aiDifficulty,
          orElse: () => AiDifficultyOption.fallback.firstWhere(
            (final AiDifficultyOption o) => o.id == s.aiDifficulty,
            orElse: () => AiDifficultyOption.fallback.first,
          ),
        );
        final String aiChipText = aiOption.name.toUpperCase();

        return ConstrainedBox(
          // maxWidth (not fixed width) so the row never overflows a
          // narrower parent — important on tablets where the controls
          // column is split flex-wise with the hero showcase.
          constraints: BoxConstraints(maxWidth: width),
          // IntrinsicHeight + CrossAxisAlignment.stretch so both
          // cards always render at the same height, regardless of
          // any future content asymmetry between them.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: ModeCard(
                    icon: Icons.smart_toy_rounded,
                    label: 'VS AI',
                    subtitle: 'Beat the bot',
                    glowColor: AppColors.brandRed,
                    // Live difficulty chip — reflects the user's last
                    // pick / current Settings value.
                    chipText: aiChipText,
                    compact: compact,
                    ultraShort: ultraShort,
                    isTablet: isTablet,
                    onTap: _onPlayVsAi,
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: ModeCard(
                    icon: Icons.people_alt_rounded,
                    label: 'PASS & PLAY',
                    subtitle: 'Couch match',
                    glowColor: AppColors.blue,
                    // Static "2 PLAYERS" chip mirrors the AI card's
                    // difficulty chip so both cards have visual
                    // symmetry instead of one card looking sparse.
                    chipText: '2 PLAYERS',
                    compact: compact,
                    ultraShort: ultraShort,
                    isTablet: isTablet,
                    onTap: _onPlay,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Bottom action row — secondary actions only. The previous "VS AI"
  /// entry moved up to a primary [ModeCard]; "ONLINE" lives here
  /// alongside the GUIDE and is gated by [_canPlayOnline] (true once
  /// the user has finished the welcome-card flow + a profile exists).
  ///
  /// Tapping ONLINE pushes [RouteName.onlineLobbyScreen]. The lobby
  /// returns either a `String` match id (random match found, room
  /// joined, or room created and joined) or `null` (cancelled).
  /// In Pass 2 we surface the match id via a snackbar — the actual
  /// game-screen integration arrives in Pass 4.
  Widget _buildActionRow({final bool compact = false}) {
    final double spacing = compact ? 10 : 14;
    final bool canPlayOnline = _canPlayOnline;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        GlassActionCard(
          icon: Icons.menu_book_rounded,
          label: 'GAME\nGUIDE',
          compact: compact,
          onTap: () =>
              Navigator.of(context).pushNamed(RouteName.guideScreen),
        ),
        SizedBox(width: spacing),
        GlassActionCard(
          icon: Icons.public_rounded,
          label: 'PLAY\nONLINE',
          // Locked while the welcome-card flow is still pending —
          // the online flow needs a confirmed profile to enqueue.
          locked: !canPlayOnline,
          lockedLabel: 'SOON',
          compact: compact,
          onTap: _onPlayOnline,
        ),
      ],
    );
  }

  /// True once the user's profile is loaded — needed before they can
  /// enter the matchmaking queue or create / join a room.
  bool get _canPlayOnline => UserService.instance.profile != null;

  /// Push the online lobby and react to whatever it pops back.
  ///
  /// On a returned match id we navigate into the GameScreen with the
  /// id baked in. The screen instantiates an [OnlineGameController]
  /// internally to drive sync; we don't need to plumb anything else
  /// through here. Bloc state is reset first so the new match starts
  /// from `GameState.initial()` and inherits the wire state cleanly
  /// on the first sync.
  Future<void> _onPlayOnline() async {
    if (!_canPlayOnline) return;
    final String? matchId = await Navigator.of(context).pushNamed<String?>(
      RouteName.onlineLobbyScreen,
    );
    if (!mounted || matchId == null) return;
    Analytics.logGameStarted();
    SettingsService.instance.gameMode = GameMode.vsOnline;
    context.read<GameBloc>().add(const ResetGameEvent());
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        settings: const RouteSettings(name: RouteName.gameScreen),
        pageBuilder: (
          final BuildContext _,
          final Animation<double> a,
          final Animation<double> b,
        ) =>
            GameScreen(onlineMatchId: matchId),
        transitionsBuilder: (
          final BuildContext _,
          final Animation<double> a,
          final Animation<double> b,
          final Widget child,
        ) {
          final Animation<double> curved =
              CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.18, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    ).then((final _) {
      // Same restoration pattern as the local game flow — snap mode
      // back to vsHuman so the next default PLAY tap doesn't
      // accidentally relaunch in online mode without a match id.
      if (!mounted) return;
      SettingsService.instance.gameMode = GameMode.vsHuman;
    });
  }

  Widget _buildFooter() {
    final double t = _e(0.7, 1.0);
    return Opacity(
      opacity: t,
      child: Text(
        '© MINI KICKERS  ·  v1.0',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.glassWhite,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(icon, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }
}


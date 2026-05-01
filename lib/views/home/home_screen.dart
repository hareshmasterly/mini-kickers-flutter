import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/routes/routes_name.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/responsive.dart';
import 'package:mini_kickers/views/game/game_screen.dart';
import 'package:mini_kickers/views/home/widget/animated_title.dart';
import 'package:mini_kickers/views/home/widget/buy_amazon_button.dart';
import 'package:mini_kickers/views/home/widget/glass_action_card.dart';
import 'package:mini_kickers/views/home/widget/hero_showcase.dart';
import 'package:mini_kickers/views/home/widget/premium_play_button.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';

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
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _onPlay() {
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
    );
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
        final double playButtonWidth = ultraShort
            ? 220
            : short
                ? 260
                : isTablet
                    ? 400
                    : 340;
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
                      child: PremiumPlayButton(
                        onPressed: _onPlay,
                        width: playButtonWidth,
                        compact: compact,
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

  Widget _buildActionRow({final bool compact = false}) {
    final double spacing = compact ? 10 : 14;
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
          icon: Icons.people_alt_rounded,
          label: 'MULTI-\nPLAYER',
          locked: true,
          compact: compact,
          onTap: ()  {
          },
        ),
        SizedBox(width: spacing),
        GlassActionCard(
          icon: Icons.smart_toy_rounded,
          label: 'VS AI',
          locked: true,
          compact: compact,
          onTap: () {},
        ),
      ],
    );
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


import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mini_kickers/bloc/game/game_bloc.dart';
import 'package:mini_kickers/data/services/faq_service.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/routes/routes_name.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/views/splash/widget/chrome_title.dart';
import 'package:mini_kickers/views/splash/widget/floating_particles.dart';
import 'package:mini_kickers/views/splash/widget/goal_burst.dart';
import 'package:mini_kickers/views/splash/widget/gold_ring.dart';
import 'package:mini_kickers/views/splash/widget/stadium_spotlights.dart';

/// World-class splash screen — premium hero layout.
///
/// LAYOUT (centered, single column):
///   • [GoldRing]          — rotating gold metallic ring around the football
///   • Football PNG        — large hero element (300px+) with elastic burst
///   • [ChromeTitle]       — bold "MINI KICKERS" in chrome-gold gradient
///   • Hairline gold rule
///   • Tagline             — small caps "INDOOR FOOTBALL BOARD GAME"
///   • [FloatingParticles] — subtle gold dust drifting upward (background)
///
/// PERFORMANCE:
///   • Static background (gradient + vignette) painted ONCE in a
///     [RepaintBoundary] — never repaints during animations.
///   • Image pre-cached via [precacheImage] before animation starts.
///   • Single master AnimationController + 1 looping spin controller.
///   • All effects use BoxShadow / gradients — zero `MaskFilter.blur`,
///     zero `BackdropFilter.blur` (the two most expensive paint ops).
///   • Total runtime 2.0 s.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _master;
  late final AnimationController _spin;
  bool _navigated = false;
  bool _imagePrecached = false;

  // Phase windows in master 0..1 space (master duration = 3.2s).
  //
  // Beats overlap on purpose — each new element joins before the
  // previous one peaks, so the eye is always pulled forward. Order:
  //
  //   spotlights ─►
  //         ball drop ─► bounce ─► settle
  //                ring reveal ─►
  //                       goal burst ╫
  //                              title ─►
  //                                  rule ─►
  //                                     tagline ─►
  //                                              outro
  static const double _spotlightsStart = 0.00;
  static const double _spotlightsEnd = 0.32;
  static const double _ballStart = 0.05;
  static const double _ballEnd = 0.42;
  static const double _ringStart = 0.30;
  static const double _ringEnd = 0.58;
  static const double _burstStart = 0.46;
  static const double _burstEnd = 0.70;
  static const double _titleStart = 0.50;
  static const double _titleEnd = 0.78;
  static const double _ruleStart = 0.72;
  static const double _ruleEnd = 0.86;
  static const double _taglineStart = 0.80;
  static const double _taglineEnd = 0.94;
  static const double _outroStart = 0.94;

  bool _impactPlayed = false;
  bool _bouncePlayed = false;
  bool _burstPlayed = false;
  bool _remoteWarmStarted = false;

  @override
  void initState() {
    super.initState();
    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )
      ..addListener(_onTick)
      ..addStatusListener((final AnimationStatus s) {
        if (s == AnimationStatus.completed) _navigateHome();
      });

    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_imagePrecached) return;
    _imagePrecached = true;
    precacheImage(const AssetImage('assets/images/football.png'), context)
        .then((final _) {
      if (!mounted) return;
      _master.forward();
      // Brief whistle on entry — uses simplified haptic+audio
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted) AudioHelper.whistle();
      });
    });

    // Pull remote defaults + FAQs in parallel with the splash animation
    // so app-launch isn't blocked. The splash always finishes in 2 s
    // regardless of fetch outcome — if the network is slow, we just fall
    // through to cached / hardcoded values and the GameBloc picks up the
    // fresh values via RefreshSettingsEvent once the fetch lands.
    if (!_remoteWarmStarted) {
      _remoteWarmStarted = true;
      unawaited(_warmRemoteData());
    }
  }

  Future<void> _warmRemoteData() async {
    // Capture the bloc now — the splash widget may be unmounted by the
    // time the fetch resolves, but the bloc lives at the app root.
    final GameBloc bloc = context.read<GameBloc>();
    await Future.wait<void>(<Future<void>>[
      SettingsService.instance.fetchRemoteDefaults(),
      FaqService.instance.fetchRemote(),
    ]);
    // Only meaningful while the bloc is still on coin-toss (i.e. the
    // user hasn't started a match yet). The handler itself guards that.
    bloc.add(const RefreshSettingsEvent());
  }

  void _onTick() {
    final double t = _master.value;
    // First bounce — when the ball lands. Heavy thump.
    if (!_impactPlayed && t >= _ballStart + (_ballEnd - _ballStart) * 0.45) {
      _impactPlayed = true;
      AudioHelper.diceResult();
    }
    // Second softer beat — second bounce as it settles.
    if (!_bouncePlayed && t >= _ballStart + (_ballEnd - _ballStart) * 0.78) {
      _bouncePlayed = true;
      AudioHelper.tokenMove();
    }
    // Climax burst at title.
    if (!_burstPlayed && t >= _burstStart) {
      _burstPlayed = true;
      AudioHelper.goal();
    }
  }

  void _navigateHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pushReplacementNamed(RouteName.homeScreen);
  }

  void _skip() {
    if (_navigated) return;
    AudioHelper.select();
    _master.stop();
    _navigateHome();
  }

  @override
  void dispose() {
    _master.dispose();
    _spin.dispose();
    super.dispose();
  }

  double _phase(final double t, final double a, final double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Scaffold(
        backgroundColor: AppColors.stadiumDeep,
        body: LayoutBuilder(
          builder: (final BuildContext ctx, final BoxConstraints cons) {
            final Size screen = Size(cons.maxWidth, cons.maxHeight);
            final double minDim = screen.shortestSide;
            // Smaller multipliers + lower clamp floors so iPhone SE
            // landscape (shortestSide ≈ 375 dp) doesn't overflow the
            // hero+title column. Tablets still cap at sensible upper
            // bounds.
            final double ballSize = (minDim * 0.30).clamp(92.0, 220.0);
            final double ringDiameter = ballSize + 40;
            final double titleFont = (minDim * 0.13).clamp(38.0, 96.0);

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // ── 1) Static premium background ──
                const RepaintBoundary(child: _PremiumBackground()),

                // ── 2) Stadium spotlights converging on centre ──
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _master,
                    builder: (final BuildContext context, final Widget? _) =>
                        StadiumSpotlights(
                      progress: _phase(
                        _master.value,
                        _spotlightsStart,
                        _spotlightsEnd,
                      ),
                    ),
                  ),
                ),

                // ── 3) Floating particles (cheap CustomPainter) ──
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (final BuildContext context, final Widget? child) =>
                        FloatingParticles(t: _spin.value),
                  ),
                ),

                // ── 4) Centered hero stack ──
                Center(
                  child: AnimatedBuilder(
                    animation: _master,
                    builder: (final BuildContext context, final Widget? _) {
                      final double t = _master.value;
                      final double ballT = _phase(t, _ballStart, _ballEnd);
                      final double ringT = _phase(t, _ringStart, _ringEnd);
                      final double burstT = _phase(t, _burstStart, _burstEnd);
                      final double titleT =
                          _phase(t, _titleStart, _titleEnd);
                      final double ruleT = _phase(t, _ruleStart, _ruleEnd);
                      final double taglineT =
                          _phase(t, _taglineStart, _taglineEnd);
                      final double outroT = _phase(t, _outroStart, 1.0);

                      return Opacity(
                        opacity: (1 - outroT).clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 1.0 + outroT * 0.05,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              // ─ Hero: ring + ball + burst ─
                              SizedBox(
                                width: ringDiameter,
                                height: ringDiameter,
                                child: Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    // Rotating gold ring (revealed clockwise)
                                    AnimatedBuilder(
                                      animation: _spin,
                                      builder: (final BuildContext context, final Widget? child) => GoldRing(
                                        progress: ringT,
                                        spinProgress: _spin.value,
                                        diameter: ringDiameter,
                                      ),
                                    ),
                                    // Goal-burst shockwave + rays at climax.
                                    // Sized larger than the ring so rays
                                    // shoot beyond it.
                                    GoalBurst(
                                      progress: burstT,
                                      diameter: ringDiameter * 1.7,
                                    ),
                                    // Football: drop, bounce, settle
                                    _BouncingFootball(
                                      progress: ballT,
                                      size: ballSize,
                                      spin: _spin.value,
                                      ringDiameter: ringDiameter,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: minDim * 0.05),
                              // Bold chrome title
                              ChromeTitle(
                                progress: titleT,
                                fontSize: titleFont,
                              ),
                              SizedBox(height: minDim * 0.025),
                              // Hairline gold rule (animates width 0→1)
                              _GoldRule(progress: ruleT, width: minDim * 0.55),
                              SizedBox(height: minDim * 0.018),
                              // Tagline
                              _Tagline(progress: taglineT),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── 4) Skip hint ──
                Positioned(
                  right: 18,
                  bottom: 14,
                  child: AnimatedBuilder(
                    animation: _master,
                    builder: (final BuildContext context, final Widget? child) {
                      final double t = _master.value;
                      final double opacity =
                          (t > 0.4 && t < 0.92 ? 0.55 : 0.0);
                      return Opacity(
                        opacity: opacity,
                        child: const Text(
                          'TAP TO SKIP',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            letterSpacing: 2.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Premium static background — radial gradient + vignette
// ═════════════════════════════════════════════════════════════════════════

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(final BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Vibrant centre → deep edges (premium green stadium)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.0,
              colors: <Color>[
                Color(0xFF1F5226),
                AppColors.stadiumDeep,
                Color(0xFF000000),
              ],
              stops: <double>[0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Soft vignette to darken edges further
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.4,
              colors: <Color>[
                Color(0x00000000),
                Color(0x66000000),
                Color(0xCC000000),
              ],
              stops: <double>[0.55, 0.85, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Football: drop from above, bounce, squash on impact, settle.
//
// Timeline within `progress` 0 → 1:
//   0.00–0.45  free-fall from above the ring (eased-in)
//   0.45–0.55  impact: squash (scaleY ↓, scaleX ↑) for ~30 ms
//   0.55–0.78  small second bounce
//   0.78–1.00  settle to rest at centre with gentle ease
//
// Spin: continuous low-rate rotation while in the air, slows once
// settled (via the master `spin` value, unchanged).
// ═════════════════════════════════════════════════════════════════════════

class _BouncingFootball extends StatelessWidget {
  const _BouncingFootball({
    required this.progress,
    required this.size,
    required this.spin,
    required this.ringDiameter,
  });

  final double progress;
  final double size;
  final double spin;
  final double ringDiameter;

  @override
  Widget build(final BuildContext context) {
    if (progress <= 0) return const SizedBox.shrink();
    final double t = progress.clamp(0.0, 1.0);

    // Vertical position: 0 = at rest in centre; -1 = a full ring height up.
    final double dropY = _dropOffset(t);
    // Squash factors. Default 1.0 = round.
    final (double scaleX, double scaleY) = _squash(t);

    final double dy = -dropY * (ringDiameter * 0.55);

    return Transform.translate(
      offset: Offset(0, dy),
      child: Transform.scale(
        scaleX: scaleX,
        scaleY: scaleY,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.goldBright.withValues(alpha: 0.55),
                blurRadius: 40,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.35),
                blurRadius: 70,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Transform.rotate(
            // Slow during fall, slows further once settled.
            angle: spin * (1.6 - t.clamp(0.0, 1.0) * 1.0),
            child: Image.asset(
              'assets/images/football.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }

  /// Returns the ball's height above rest (1.0 = high above, 0.0 = on rest).
  double _dropOffset(final double t) {
    if (t <= 0.45) {
      // Free-fall: starts high, ease-in toward zero.
      final double f = t / 0.45;
      return 1.0 - Curves.easeInQuad.transform(f);
    }
    if (t <= 0.55) {
      // Impact compression — already at floor; no Y movement.
      return 0.0;
    }
    if (t <= 0.78) {
      // Second bounce — small parabola peaking around 0.20.
      final double f = (t - 0.55) / 0.23;
      return sin(f * pi) * 0.22;
    }
    return 0.0;
  }

  /// Returns `(scaleX, scaleY)` for squash-and-stretch.
  (double, double) _squash(final double t) {
    // Pre-impact stretch (ball elongates vertically as it falls fast).
    if (t > 0.30 && t < 0.45) {
      final double f = (t - 0.30) / 0.15;
      final double stretch = f * 0.08;
      return (1.0 - stretch * 0.5, 1.0 + stretch);
    }
    // Impact squash (ball flattens).
    if (t >= 0.45 && t <= 0.55) {
      final double f = (t - 0.45) / 0.10;
      // Pulse: 0 → max squash at 0.5 → back to round at 1.
      final double s = sin(f * pi);
      return (1.0 + s * 0.22, 1.0 - s * 0.28);
    }
    // Tiny second-bounce squash near top of arc (none) and bottom.
    if (t >= 0.74 && t <= 0.80) {
      final double f = (t - 0.74) / 0.06;
      final double s = sin(f * pi);
      return (1.0 + s * 0.08, 1.0 - s * 0.10);
    }
    return (1.0, 1.0);
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Hairline gold rule that scribes from center outward
// ═════════════════════════════════════════════════════════════════════════

class _GoldRule extends StatelessWidget {
  const _GoldRule({required this.progress, required this.width});
  final double progress;
  final double width;

  @override
  Widget build(final BuildContext context) {
    final double t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    return SizedBox(
      width: width,
      height: 6,
      child: Center(
        child: Container(
          width: width * t,
          height: 1.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                AppColors.goldDeep.withValues(alpha: 0),
                AppColors.goldBright,
                AppColors.goldShine,
                AppColors.goldBright,
                AppColors.goldDeep.withValues(alpha: 0),
              ],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.goldBright.withValues(alpha: 0.6 * t),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Tagline — small caps under the hairline rule
// ═════════════════════════════════════════════════════════════════════════

class _Tagline extends StatelessWidget {
  const _Tagline({required this.progress});
  final double progress;

  @override
  Widget build(final BuildContext context) {
    if (progress <= 0) return const SizedBox.shrink();
    final double t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - t)),
        child: Text(
          'INDOOR  ·  FOOTBALL  ·  BOARD GAME',
          style: AppFonts.bebasNeue(
            fontSize: 14,
            letterSpacing: 5,
            color: Colors.white.withValues(alpha: 0.85),
            shadows: <Shadow>[
              Shadow(
                color: AppColors.goldBright.withValues(alpha: 0.4),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

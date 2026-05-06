import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mini_kickers/data/models/remote_avatar.dart';
import 'package:mini_kickers/data/models/user_profile.dart';
import 'package:mini_kickers/data/services/avatar_service.dart';
import 'package:mini_kickers/data/services/user_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/handle_generator.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';

/// User-facing profile screen. Shows the user's avatar, handle,
/// match stats, and lets them change their avatar / handle (with
/// rate-limit awareness) inline via small pencil-edit affordances.
///
/// Design language: a "player card" header with subtle sparkle
/// particles + a pulsing gold glow on the avatar so the screen feels
/// like a premium trading-card profile rather than a settings page.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    UserService.instance.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    UserService.instance.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(final BuildContext context) {
    final UserProfile? profile = UserService.instance.profile;
    return Scaffold(
      backgroundColor: AppColors.stadiumDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const StadiumBackground(),
          SafeArea(
            bottom: Platform.isIOS ? false : true,
            child: profile == null
                ? const _LoadingState()
                : _buildContent(context, profile),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(final BuildContext context, final UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: <Widget>[
          _Header(),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _PlayerCard(
                    profile: profile,
                    onAvatarTap: () => _openAvatarSheet(context, profile),
                    onHandleTap: _onHandleEditTap,
                  ),
                  const SizedBox(height: 14),
                  _StatsCard(profile: profile),
                  const SizedBox(height: 12),
                  _MemberSinceFooter(profile: profile),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tapped pencil next to the handle. If still in cooldown, shows a
  /// snackbar with the time remaining instead of opening the editor —
  /// keeping the affordance visible at all times communicates "you
  /// CAN edit, just not yet" better than a hidden / greyed-out icon.
  void _onHandleEditTap() {
    final DateTime? next = UserService.instance.nextHandleChangeAt;
    if (next == null) {
      _openHandleSheet(context, UserService.instance.profile!);
      return;
    }
    AudioHelper.select();
    final Duration remaining = next.difference(DateTime.now());
    final String wait = _formatRemaining(remaining);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('You can change your name again in $wait')),
    );
  }

  static String _formatRemaining(final Duration r) {
    if (r.inDays > 0) return '${r.inDays}d ${r.inHours % 24}h';
    if (r.inHours > 0) return '${r.inHours}h ${r.inMinutes % 60}m';
    return '${r.inMinutes.clamp(1, 60)}m';
  }

  Future<void> _openAvatarSheet(
    final BuildContext context,
    final UserProfile profile,
  ) async {
    AudioHelper.select();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (final BuildContext _) =>
          _AvatarPickerSheet(currentAvatarId: profile.avatarId),
    );
  }

  Future<void> _openHandleSheet(
    final BuildContext context,
    final UserProfile profile,
  ) async {
    AudioHelper.select();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (final BuildContext _) =>
          _HandleEditorSheet(currentHandle: profile.handle),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Header (back button + screen title)
// ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(final BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: () {
              AudioHelper.select();
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            },
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'PROFILE',
            style: AppFonts.bebasNeue(
              fontSize: 32,
              letterSpacing: 6,
              color: Colors.white,
              shadows: <Shadow>[
                Shadow(
                  color: AppColors.accent.withValues(alpha: 0.45),
                  blurRadius: 24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Player Card — avatar + handle + inline pencil edits
// ─────────────────────────────────────────────────────────────────────

class _PlayerCard extends StatefulWidget {
  const _PlayerCard({
    required this.profile,
    required this.onAvatarTap,
    required this.onHandleTap,
  });

  final UserProfile profile;
  final VoidCallback onAvatarTap;
  final VoidCallback onHandleTap;

  @override
  State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard>
    with TickerProviderStateMixin {
  late final AnimationController _glowPulse;
  late final AnimationController _bounce;
  late final AnimationController _sparkle;

  @override
  void initState() {
    super.initState();
    _glowPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _sparkle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _glowPulse.dispose();
    _bounce.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final String emoji = HandleGenerator.emojiFor(widget.profile.avatarId);
    final bool inCooldown = !UserService.instance.canChangeHandle;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            const Color(0xFF152C18),
            Color.lerp(const Color(0xFF0A150A), AppColors.accent, 0.08)!,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.goldBright.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.goldBright.withValues(alpha: 0.32),
            blurRadius: 40,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          // Subtle sparkle dots — drawn behind the content for depth.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _sparkle,
                builder: (final BuildContext _, final Widget? child) =>
                    CustomPaint(painter: _SparklesPainter(t: _sparkle.value)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 20, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _AvatarWithEdit(
                  emoji: emoji,
                  onTap: widget.onAvatarTap,
                  glowPulse: _glowPulse,
                  bounce: _bounce,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _HandleWithEdit(
                        handle: widget.profile.handle,
                        onTap: widget.onHandleTap,
                        inCooldown: inCooldown,
                      ),
                      if (widget.profile.displayName.isNotEmpty &&
                          widget.profile.displayName !=
                              widget.profile.handle) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          widget.profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _TierBadge(matchesPlayed: widget.profile.matchesPlayed),
                      const SizedBox(height: 8),
                      _MatchSummary(profile: widget.profile),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Big circular avatar with a small gold "edit" badge floating at the
/// bottom-right corner. The whole thing is one tap target — pencil
/// is just a visual affordance, not a separate hit zone.
class _AvatarWithEdit extends StatelessWidget {
  const _AvatarWithEdit({
    required this.emoji,
    required this.onTap,
    required this.glowPulse,
    required this.bounce,
  });

  final String emoji;
  final VoidCallback onTap;
  final AnimationController glowPulse;
  final AnimationController bounce;

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[glowPulse, bounce]),
      builder: (final BuildContext context, final Widget? child) {
        final double pulse = glowPulse.value;
        final double float = sin(bounce.value * pi) * 4;
        return Transform.translate(
          offset: Offset(0, -float),
          child: GestureDetector(
            onTap: () {
              AudioHelper.select();
              onTap();
            },
            child: SizedBox(
              width: 124,
              height: 124,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  // Pulsing outer glow ring — sits behind the avatar.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: AppColors.goldBright.withValues(
                                alpha: 0.35 + pulse * 0.35,
                              ),
                              blurRadius: 22 + pulse * 14,
                              spreadRadius: 2 + pulse * 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Avatar disc.
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.25, -0.35),
                        colors: <Color>[Color(0xFF333333), Color(0xFF111111)],
                      ),
                      border: Border.all(color: AppColors.goldShine, width: 3),
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 64)),
                    ),
                  ),
                  // Edit badge — small gold circle with pencil glyph,
                  // floats over the bottom-right corner of the avatar.
                  Positioned(right: 0, bottom: 4, child: _EditBadge()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Handle text with an inline edit pencil. When the user is within
/// the 7-day cooldown the pencil shows a clock icon instead — tapping
/// it surfaces a snackbar with the time remaining (handled in the
/// parent screen).
class _HandleWithEdit extends StatelessWidget {
  const _HandleWithEdit({
    required this.handle,
    required this.onTap,
    required this.inCooldown,
  });

  final String handle;
  final VoidCallback onTap;
  final bool inCooldown;

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      onTap: () {
        AudioHelper.select();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        // Left-aligned because we now sit inside the player card's
        // right column (crossAxisAlignment.start). MainAxisSize.min
        // means the row hugs the handle text + pencil.
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: ShaderMask(
              shaderCallback: (final Rect bounds) => const LinearGradient(
                colors: <Color>[
                  AppColors.goldDeep,
                  AppColors.goldShine,
                  AppColors.goldDeep,
                ],
              ).createShader(bounds),
              child: Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.bebasNeue(
                  fontSize: 28,
                  letterSpacing: 2.4,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: inCooldown
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppColors.goldShine.withValues(alpha: 0.7),
                width: 1.2,
              ),
            ),
            child: Icon(
              inCooldown ? Icons.lock_clock_rounded : Icons.edit_rounded,
              size: 14,
              color: inCooldown
                  ? Colors.white.withValues(alpha: 0.45)
                  : AppColors.goldShine,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small gold circle with a pencil glyph — anchored to the bottom-
/// right of the avatar to communicate "tap to edit" without taking up
/// a row of its own.
class _EditBadge extends StatelessWidget {
  @override
  Widget build(final BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.goldShine, Color(0xFFFF9800)],
        ),
        border: Border.all(color: Colors.white, width: 2.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.goldBright.withValues(alpha: 0.6),
            blurRadius: 10,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Colors.black45,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF1B1B1B)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Tier system — gives the right side of the player card something
// meaningful to look at instead of empty space, and gives kids a
// long-term progression goal ("just 5 more matches and I'm a PRO!").
//
// Tier thresholds are deliberately easy at the low end so even
// casual users hit a milestone within their first session — no
// "0 / 100 ROOKIE" sad state.
// ─────────────────────────────────────────────────────────────────────

class _Tier {
  const _Tier({required this.label, required this.emoji, required this.color});

  final String label;
  final String emoji;
  final Color color;

  /// Picks the tier for a given match count. Order matters — list is
  /// scanned high → low and the first matching threshold wins.
  static _Tier forMatchCount(final int matches) {
    if (matches >= 100) {
      return const _Tier(
        label: 'LEGEND',
        emoji: '👑',
        color: Color(0xFFFFD700),
      );
    }
    if (matches >= 25) {
      return const _Tier(
        label: 'VETERAN',
        emoji: '🔥',
        color: AppColors.brandRed,
      );
    }
    if (matches >= 5) {
      return const _Tier(label: 'PRO', emoji: '⚖️', color: AppColors.accent);
    }
    return const _Tier(
      label: 'ROOKIE',
      emoji: '🌱',
      color: AppColors.limeBright,
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.matchesPlayed});

  final int matchesPlayed;

  @override
  Widget build(final BuildContext context) {
    final _Tier tier = _Tier.forMatchCount(matchesPlayed);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tier.color.withValues(alpha: 0.55),
          width: 1.4,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tier.color.withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(tier.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            tier.label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact one-line summary of the user's record — sits below the
/// tier badge to fill the right-side white space with information
/// rather than emptiness. Kept terse so the player card stays
/// visually quiet; the full breakdown lives in [_StatsCard] below.
class _MatchSummary extends StatelessWidget {
  const _MatchSummary({required this.profile});

  final UserProfile profile;

  @override
  Widget build(final BuildContext context) {
    if (profile.matchesPlayed == 0) {
      return Text(
        'Play your first match!',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Row(
      children: <Widget>[
        _SummaryDot(icon: '🎮', value: profile.matchesPlayed.toString()),
        const SizedBox(width: 12),
        _SummaryDot(icon: '🏆', value: profile.matchesWon.toString()),
        const SizedBox(width: 12),
        _SummaryDot(icon: '⚽', value: profile.goalsScored.toString()),
      ],
    );
  }
}

class _SummaryDot extends StatelessWidget {
  const _SummaryDot({required this.icon, required this.value});

  final String icon;
  final String value;

  @override
  Widget build(final BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppFonts.bebasNeue(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.85),
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// Painter for a few subtle sparkle dots inside the player card. The
/// twinkles use a CustomPaint instead of layered widgets because we
/// want them positioned freely on the gold surface — laying them out
/// in a Stack of Positioned widgets is fiddlier than just a paint.
class _SparklesPainter extends CustomPainter {
  _SparklesPainter({required this.t});

  /// 0 → 1 looping value driving the twinkle phase.
  final double t;

  static const List<Offset> _normalisedPositions = <Offset>[
    Offset(0.10, 0.18),
    Offset(0.22, 0.74),
    Offset(0.86, 0.16),
    Offset(0.78, 0.78),
    Offset(0.50, 0.06),
    Offset(0.94, 0.50),
    Offset(0.06, 0.50),
  ];

  @override
  void paint(final Canvas canvas, final Size size) {
    final Paint paint = Paint()
      ..color = AppColors.goldShine.withValues(alpha: 0.55);
    for (int i = 0; i < _normalisedPositions.length; i++) {
      final Offset n = _normalisedPositions[i];
      // Each sparkle has a phase offset so they don't twinkle in sync.
      final double phase = (t + i * 0.13) % 1.0;
      final double tw = sin(phase * 2 * pi).abs(); // 0..1
      final double radius = 1.4 + tw * 1.6;
      paint.color = AppColors.goldShine.withValues(alpha: 0.25 + tw * 0.55);
      canvas.drawCircle(
        Offset(n.dx * size.width, n.dy * size.height),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant final _SparklesPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────
// Stats Card — match counts + derived percentages
// ─────────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.profile});

  final UserProfile profile;

  /// Win rate as a percentage 0–100, or null when no matches played
  /// yet (we hide the row instead of showing "0%").
  double? get _winRate {
    if (profile.matchesPlayed == 0) return null;
    return (profile.matchesWon / profile.matchesPlayed) * 100;
  }

  /// Average goals scored per match, or null for fresh accounts.
  double? get _goalsPerMatch {
    if (profile.matchesPlayed == 0) return null;
    return profile.goalsScored / profile.matchesPlayed;
  }

  @override
  Widget build(final BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandRed.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.brandRed.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: AppColors.brandRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'STATS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _StatTile(
                      emoji: '🎮',
                      label: 'Played',
                      value: profile.matchesPlayed.toString(),
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      emoji: '🏆',
                      label: 'Won',
                      value: profile.matchesWon.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _StatTile(
                      emoji: '🤝',
                      label: 'Drawn',
                      value: profile.matchesDrawn.toString(),
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      emoji: '😬',
                      label: 'Lost',
                      value: profile.matchesLost.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _StatTile(
                      emoji: '⚽',
                      label: 'Goals',
                      value: profile.goalsScored.toString(),
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      emoji: '🥅',
                      label: 'Conceded',
                      value: profile.goalsConceded.toString(),
                    ),
                  ),
                ],
              ),
              if (_winRate != null) ...<Widget>[
                const SizedBox(height: 14),
                _DerivedStatBar(
                  label: 'Win rate',
                  emoji: '📈',
                  percent: _winRate!,
                  rightLabel: '${_winRate!.toStringAsFixed(0)}%',
                  trackColor: AppColors.limeBright,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Text('⚽', style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    const Text(
                      'Goals per match',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _goalsPerMatch!.toStringAsFixed(1),
                      style: AppFonts.bebasNeue(
                        fontSize: 18,
                        color: AppColors.goldShine,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.emoji,
    required this.label,
    required this.value,
  });

  final String emoji;
  final String label;
  final String value;

  @override
  Widget build(final BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: AppFonts.bebasNeue(
                    fontSize: 24,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim labelled progress bar used for derived percentages (win
/// rate). Gives the stats card a sense of progression beyond the
/// raw counts.
class _DerivedStatBar extends StatelessWidget {
  const _DerivedStatBar({
    required this.label,
    required this.emoji,
    required this.percent,
    required this.rightLabel,
    required this.trackColor,
  });

  final String label;
  final String emoji;

  /// 0–100.
  final double percent;
  final String rightLabel;
  final Color trackColor;

  @override
  Widget build(final BuildContext context) {
    final double frac = (percent / 100).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              rightLabel,
              style: AppFonts.bebasNeue(
                fontSize: 18,
                color: trackColor,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: <Widget>[
              Container(height: 6, color: Colors.white.withValues(alpha: 0.08)),
              FractionallySizedBox(
                widthFactor: frac,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        trackColor.withValues(alpha: 0.6),
                        trackColor,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// "Member since" footer
// ─────────────────────────────────────────────────────────────────────

class _MemberSinceFooter extends StatelessWidget {
  const _MemberSinceFooter({required this.profile});

  final UserProfile profile;

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(final BuildContext context) {
    final DateTime? created = profile.createdAt?.toDate();
    if (created == null) return const SizedBox.shrink();
    final String label =
        'Member since ${_months[created.month - 1]} ${created.year}';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 11,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Avatar picker dialog
// ─────────────────────────────────────────────────────────────────────

class _AvatarPickerSheet extends StatefulWidget {
  const _AvatarPickerSheet({required this.currentAvatarId});

  final String currentAvatarId;

  @override
  State<_AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<_AvatarPickerSheet> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentAvatarId;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final bool ok = await UserService.instance.changeAvatar(_selected);
    if (!mounted) return;
    if (ok) {
      AudioHelper.select();
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save avatar — try again")),
      );
    }
  }

  @override
  Widget build(final BuildContext context) {
    final List<RemoteAvatar> avatars = AvatarService.instance.all;
    return _SheetShell(
      title: 'CHOOSE AVATAR',
      subtitle: 'Pick a face to wear in your matches',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Responsive grid — column count picked from the container
          // width so tiles stay a comfortable ~52-72 px regardless of
          // form factor. Without this we got cramped 6-col grids on
          // landscape phones and stretched ones on tablets.
          LayoutBuilder(
            builder: (final BuildContext _, final BoxConstraints cons) {
              final double w = cons.maxWidth;
              final int cols = w >= 560
                  ? 8
                  : w >= 440
                  ? 7
                  : w >= 340
                  ? 6
                  : w >= 260
                  ? 5
                  : 4;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemCount: avatars.length,
                itemBuilder: (final BuildContext _, final int i) {
                  final RemoteAvatar a = avatars[i];
                  final bool selected = a.id == _selected;
                  return GestureDetector(
                    onTap: () {
                      AudioHelper.select();
                      setState(() => _selected = a.id);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.accent.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.18),
                          width: selected ? 1.8 : 1,
                        ),
                        boxShadow: selected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            a.emoji,
                            style: const TextStyle(fontSize: 30),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          _SheetSaveButton(
            label: _saving ? 'Saving…' : 'Save',
            onTap: _saving || _selected == widget.currentAvatarId
                ? null
                : _save,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Handle editor dialog
// ─────────────────────────────────────────────────────────────────────

class _HandleEditorSheet extends StatefulWidget {
  const _HandleEditorSheet({required this.currentHandle});

  final String currentHandle;

  @override
  State<_HandleEditorSheet> createState() => _HandleEditorSheetState();
}

class _HandleEditorSheetState extends State<_HandleEditorSheet> {
  late final TextEditingController _controller;
  Timer? _debounce;
  bool _checking = false;
  bool _saving = false;

  /// null = no result yet, true = available, false = taken / invalid.
  bool? _available;
  String? _validationError;

  static final RegExp _allowedChars = RegExp(r'^[A-Za-z0-9_]+$');
  static const int _minLen = 3;
  static const int _maxLen = 15;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentHandle);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(final String raw) {
    _debounce?.cancel();
    final String trimmed = raw.trim();

    final String? err = _validate(trimmed);
    if (err != null) {
      setState(() {
        _validationError = err;
        _available = null;
        _checking = false;
      });
      return;
    }
    if (trimmed == widget.currentHandle) {
      setState(() {
        _validationError = null;
        _available = null;
        _checking = false;
      });
      return;
    }

    setState(() {
      _validationError = null;
      _checking = true;
      _available = null;
    });
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final bool ok = await UserService.instance.isHandleAvailable(trimmed);
      if (!mounted) return;
      if (_controller.text.trim() != trimmed) return;
      setState(() {
        _checking = false;
        _available = ok;
      });
    });
  }

  String? _validate(final String s) {
    if (s.isEmpty) return null;
    if (s.length < _minLen) return 'At least $_minLen characters';
    if (s.length > _maxLen) return 'At most $_maxLen characters';
    if (!_allowedChars.hasMatch(s)) {
      return 'Letters, numbers, and _ only';
    }
    return null;
  }

  Future<void> _save() async {
    final String candidate = _controller.text.trim();
    if (_saving) return;
    if (candidate.isEmpty || candidate == widget.currentHandle) return;
    setState(() => _saving = true);
    final HandleChangeResult result = await UserService.instance.changeHandle(
      candidate,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case HandleChangeResult.ok:
        AudioHelper.select();
        Navigator.of(context).pop();
        break;
      case HandleChangeResult.taken:
        setState(() => _available = false);
        break;
      case HandleChangeResult.cooldown:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can change your handle once every 7 days'),
          ),
        );
        break;
      case HandleChangeResult.invalid:
        break;
      case HandleChangeResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save handle — try again")),
        );
        break;
    }
  }

  bool get _canSave =>
      !_saving &&
      !_checking &&
      _validationError == null &&
      _available == true &&
      _controller.text.trim() != widget.currentHandle &&
      _controller.text.trim().isNotEmpty;

  @override
  Widget build(final BuildContext context) {
    return _SheetShell(
      title: 'CHANGE HANDLE',
      subtitle: 'Letters, numbers, and underscores. $_minLen–$_maxLen chars.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: _maxLen,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              LengthLimitingTextInputFormatter(_maxLen),
            ],
            textInputAction: TextInputAction.done,
            onChanged: _onChanged,
            onSubmitted: (final _) {
              if (_canSave) _save();
            },
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              counterText: '',
              hintText: 'NewHandle42',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _StatusLine(
            checking: _checking,
            validationError: _validationError,
            available: _available,
            isUnchanged:
                _controller.text.trim() == widget.currentHandle &&
                _controller.text.trim().isNotEmpty,
          ),
          const SizedBox(height: 16),
          _SheetSaveButton(
            label: _saving ? 'Saving…' : 'Save',
            onTap: _canSave ? _save : null,
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.checking,
    required this.validationError,
    required this.available,
    required this.isUnchanged,
  });

  final bool checking;
  final String? validationError;
  final bool? available;
  final bool isUnchanged;

  @override
  Widget build(final BuildContext context) {
    String text;
    Color color;
    IconData? icon;

    if (validationError != null) {
      text = validationError!;
      color = AppColors.brandRed;
      icon = Icons.error_outline_rounded;
    } else if (isUnchanged) {
      text = 'This is your current handle';
      color = Colors.white.withValues(alpha: 0.55);
    } else if (checking) {
      text = 'Checking availability…';
      color = Colors.white.withValues(alpha: 0.55);
    } else if (available == true) {
      text = 'Available!';
      color = AppColors.limeBright;
      icon = Icons.check_circle_outline_rounded;
    } else if (available == false) {
      text = 'Taken — try another';
      color = AppColors.brandRed;
      icon = Icons.error_outline_rounded;
    } else {
      text = ' ';
      color = Colors.transparent;
    }

    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared dialog shell
// ─────────────────────────────────────────────────────────────────────

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final bool compact = screen.height < 400;
    final bool isTablet = !compact && screen.shortestSide >= 600;
    final double maxWidth = isTablet ? 640 : 520;
    final EdgeInsets cardPad = compact
        ? const EdgeInsets.fromLTRB(20, 16, 20, 16)
        : isTablet
        ? const EdgeInsets.fromLTRB(36, 28, 36, 26)
        : const EdgeInsets.fromLTRB(24, 22, 24, 22);
    final double titleFont = compact ? 22 : (isTablet ? 32 : 26);
    final double subtitleFont = compact ? 11 : (isTablet ? 14 : 12);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: cardPad,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF101F10), Color(0xFF0A150A)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.goldBright.withValues(alpha: 0.55),
              width: 2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.goldBright.withValues(alpha: 0.32),
                blurRadius: 36,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black87,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppFonts.bebasNeue(
                    fontSize: titleFont,
                    letterSpacing: 4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: subtitleFont,
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: compact ? 12 : 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetSaveButton extends StatelessWidget {
  const _SheetSaveButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) {
    final bool disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: GestureDetector(
        onTap: disabled
            ? null
            : () {
                AudioHelper.select();
                onTap!();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[AppColors.goldBright, Color(0xFFFF9800)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.goldBright.withValues(alpha: 0.5),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: AppFonts.bebasNeue(
                fontSize: 18,
                letterSpacing: 3,
                color: const Color(0xFF1B1B1B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Loading state
// ─────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(final BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(color: AppColors.accent),
          const SizedBox(height: 16),
          Text(
            'Loading your profile…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

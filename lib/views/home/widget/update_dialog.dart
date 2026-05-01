import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mini_kickers/data/models/remote_app_update_settings.dart';
import 'package:mini_kickers/data/services/app_update_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/responsive.dart';
import 'package:url_launcher/url_launcher.dart';

/// Beautiful, modern in-app update prompt.
///
/// Visual: glassmorphic card on a darkened backdrop, with a glowing
/// download icon, headline + body, and 1 or 2 CTA buttons depending on
/// whether the update is FORCE (only "Update") or OPTIONAL (also a
/// quieter "Maybe later"). Animated entry (scale + fade) and a soft
/// shimmer sweep over the icon to draw attention.
///
/// Force-update mode also disables tap-outside-to-dismiss + Android
/// back-button so the user truly can't get past it without updating.
///
/// Show via:
/// ```dart
/// final UpdateCheckResult r = await AppUpdateService.instance.check();
/// if (r.shouldShow) {
///   await showUpdateDialog(context, result: r);
/// }
/// ```
Future<void> showUpdateDialog(
  final BuildContext context, {
  required final UpdateCheckResult result,
}) async {
  final RemoteAppUpdateSettings? settings = result.settings;
  if (settings == null || result.storeUrl.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: !settings.isForceUpdateEnable,
    barrierColor: Colors.black87,
    builder: (final BuildContext ctx) => _UpdateDialog(
      settings: settings,
      storeUrl: result.storeUrl,
    ),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.settings, required this.storeUrl});

  final RemoteAppUpdateSettings settings;
  final String storeUrl;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _shimmer;
  late final AnimationController _orbit;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _entry.dispose();
    _shimmer.dispose();
    _orbit.dispose();
    super.dispose();
  }

  Future<void> _onUpdate() async {
    AudioHelper.select();
    final Uri uri = Uri.parse(widget.storeUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silent — store URL might be malformed; we don't surface this
      // to the user (worst case they tap again or update manually).
    }
  }

  void _onMaybeLater() {
    AudioHelper.select();
    AppUpdateService.instance.markDismissed();
    Navigator.of(context).pop();
  }

  @override
  Widget build(final BuildContext context) {
    final RemoteAppUpdateSettings s = widget.settings;
    final bool isForce = s.isForceUpdateEnable;
    final Size screen = MediaQuery.of(context).size;
    // Three tiers — compact (landscape phones h<520) needs much
    // smaller paddings + icon than the previous "phone vs tablet"
    // split, otherwise the card overflows the viewport (the bug we
    // just fixed in game_over_widget had the exact same root cause).
    final bool compact = Responsive.isCompact(context);
    final bool isTablet = !compact && screen.shortestSide >= 600;

    final double maxWidth = isTablet ? 560 : (compact ? 380 : 420);
    final EdgeInsets cardPad = compact
        ? const EdgeInsets.fromLTRB(20, 14, 20, 14)
        : isTablet
            ? const EdgeInsets.fromLTRB(36, 36, 36, 28)
            : const EdgeInsets.fromLTRB(26, 28, 26, 22);
    final double iconBoxSize = compact ? 44 : (isTablet ? 96 : 72);
    final double titleFont = compact ? 22 : (isTablet ? 36 : 28);
    final double messageFont = compact ? 11 : (isTablet ? 15 : 13);
    final double btnVPad = compact ? 10 : (isTablet ? 16 : 13);
    final double primaryBtnFont = compact ? 13 : (isTablet ? 17 : 14);
    final double cancelBtnFont = compact ? 11 : (isTablet ? 14 : 12);
    // Inter-element spacing also shrinks in compact so we don't burn
    // vertical space between sections of the card.
    final double gapAfterIcon = compact ? 10 : 18;
    final double gapAfterTitle = compact ? 6 : 10;
    final double gapBeforeBadge = compact ? 8 : 14;
    final double gapBeforePrimary = compact ? 12 : 22;
    final double gapBeforeCancel = compact ? 6 : 10;
    // Cap the card so its content can NEVER outgrow the viewport.
    // SingleChildScrollView (added below) makes any leftover content
    // scrollable rather than overflowing into a yellow-stripe error.
    final double maxCardHeight = screen.height - 24;

    return PopScope<dynamic>(
      // Force-update: block Android back / iOS swipe-back so the user
      // cannot dismiss the dialog without going to the store.
      canPop: !isForce,
      // Material(type: transparency) provides the Material ancestor that
      // Text widgets need to inherit a proper DefaultTextStyle. Without
      // this wrapper, every Text in the dialog gets Flutter's yellow
      // double-underline debug indicator (the "no Material ancestor"
      // warning). Other dialogs in the app avoid this because they use
      // the `Dialog` widget — we don't, so we wrap manually here.
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
        animation: _entry,
        builder: (final BuildContext context, final Widget? child) {
          final double t = Curves.easeOutCubic.transform(_entry.value);
          final double scaleT = Curves.elasticOut.transform(
            _entry.value.clamp(0.0, 1.0),
          );
          return Center(
            child: Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.7 + scaleT * 0.3,
                child: child,
              ),
            ),
          );
        },
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxCardHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.brandYellow.withValues(alpha: 0.55),
                        width: 2,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color:
                              AppColors.brandYellow.withValues(alpha: 0.42),
                          blurRadius: 50,
                          spreadRadius: 2,
                        ),
                        const BoxShadow(
                          color: Colors.black87,
                          blurRadius: 30,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    // SingleChildScrollView is the safety net: if the
                    // device is so cramped that even compact-tier
                    // sizing overflows (rare — landscape phones with
                    // accessibility text scaling, foldables in flex
                    // mode), the user can scroll the card content
                    // instead of seeing a yellow-stripe error.
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _GlowingIcon(
                            shimmer: _shimmer,
                            orbit: _orbit,
                            size: iconBoxSize,
                            isForce: isForce,
                          ),
                          SizedBox(height: gapAfterIcon),
                          ShaderMask(
                            shaderCallback: (final Rect bounds) =>
                                const LinearGradient(
                              colors: <Color>[
                                AppColors.goldDeep,
                                AppColors.goldShine,
                                AppColors.goldDeep,
                              ],
                            ).createShader(bounds),
                            child: Text(
                              s.title.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: AppFonts.bebasNeue(
                                fontSize: titleFont,
                                color: Colors.white,
                                letterSpacing: 1.6,
                                shadows: <Shadow>[
                                  Shadow(
                                    color: AppColors.brandYellow.withValues(
                                      alpha: 0.55,
                                    ),
                                    blurRadius: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: gapAfterTitle),
                          Text(
                            s.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: messageFont,
                              height: 1.45,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (isForce) ...<Widget>[
                            SizedBox(height: gapBeforeBadge),
                            _ForceBadge(),
                          ],
                          SizedBox(height: gapBeforePrimary),
                          _PrimaryButton(
                            label: s.okBtnText,
                            fontSize: primaryBtnFont,
                            vPad: btnVPad,
                            onPressed: _onUpdate,
                          ),
                          if (!isForce) ...<Widget>[
                            SizedBox(height: gapBeforeCancel),
                            TextButton(
                              onPressed: _onMaybeLater,
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    Colors.white.withValues(alpha: 0.7),
                                padding: EdgeInsets.symmetric(
                                  vertical: btnVPad - 2,
                                  horizontal: 22,
                                ),
                              ),
                              child: Text(
                                s.cancelBtnText.toUpperCase(),
                                style: TextStyle(
                                  fontSize: cancelBtnFont,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Circular icon badge with a rotating glow ring + shimmering download
/// arrow. The "wow" element of the dialog.
class _GlowingIcon extends StatelessWidget {
  const _GlowingIcon({
    required this.shimmer,
    required this.orbit,
    required this.size,
    required this.isForce,
  });

  final Animation<double> shimmer;
  final Animation<double> orbit;
  final double size;
  final bool isForce;

  @override
  Widget build(final BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[shimmer, orbit]),
      builder: (final BuildContext context, final Widget? _) {
        final double s = shimmer.value;
        final double o = orbit.value;
        return SizedBox(
          width: size * 1.4,
          height: size * 1.4,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Outer rotating gradient halo
              Transform.rotate(
                angle: o * pi * 2,
                child: Container(
                  width: size * 1.35,
                  height: size * 1.35,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: <Color>[
                        AppColors.brandYellow.withValues(alpha: 0),
                        AppColors.brandYellow.withValues(alpha: 0.85),
                        AppColors.brandYellow.withValues(alpha: 0),
                        AppColors.goldShine.withValues(alpha: 0.6),
                        AppColors.brandYellow.withValues(alpha: 0),
                      ],
                      stops: const <double>[0, 0.25, 0.5, 0.75, 1],
                    ),
                  ),
                ),
              ),
              // Inner solid disc (mask middle of the halo)
              Container(
                width: size * 1.18,
                height: size * 1.18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF101F10),
                ),
              ),
              // Pulsing inner glow disc
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      AppColors.brandYellow
                          .withValues(alpha: 0.55 + s * 0.25),
                      AppColors.brandYellow.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // The icon — "system_update" reads as a proper update
              // arrow + frame; switches to "warning" for force update.
              Icon(
                isForce
                    ? Icons.system_security_update_warning_rounded
                    : Icons.system_update_rounded,
                size: size * 0.6,
                color: Colors.white,
                shadows: <Shadow>[
                  Shadow(
                    color: AppColors.brandYellow.withValues(alpha: 0.85),
                    blurRadius: 20,
                  ),
                ],
              ),
              // Diagonal shimmer sweep across the icon
              ClipOval(
                child: SizedBox(
                  width: size * 1.18,
                  height: size * 1.18,
                  child: Transform.translate(
                    offset: Offset(
                      (s * 2 - 1) * size * 1.2,
                      (s * 2 - 1) * size * 1.2,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.18),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const <double>[0, 0.5, 1],
                        ),
                      ),
                    ),
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

/// Small "REQUIRED" pill shown above the buttons in force-update mode
/// so the user understands why there's no Cancel option.
class _ForceBadge extends StatelessWidget {
  @override
  Widget build(final BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3344).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFF3344).withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.lock_rounded,
            size: 12,
            color: Color(0xFFFF6677),
          ),
          const SizedBox(width: 6),
          Text(
            'REQUIRED UPDATE',
            style: TextStyle(
              color: const Color(0xFFFF6677),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Big primary CTA — gradient gold pill, full width, with a chevron
/// icon to telegraph "tap me, you're going somewhere".
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.fontSize,
    required this.vPad,
    required this.onPressed,
  });

  final String label;
  final double fontSize;
  final double vPad;
  final VoidCallback onPressed;

  @override
  Widget build(final BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: vPad),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ).copyWith(
          backgroundBuilder: (
            final BuildContext context,
            final Set<WidgetState> states,
            final Widget? child,
          ) {
            return Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    AppColors.goldShine,
                    AppColors.brandYellow,
                    AppColors.goldDeep,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color:
                        AppColors.brandYellow.withValues(alpha: 0.55),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(child: child),
            );
          },
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_download_rounded, size: 20),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 22),
          ],
        ),
      ),
    );
  }
}

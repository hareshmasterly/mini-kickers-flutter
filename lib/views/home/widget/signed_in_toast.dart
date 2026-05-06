import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/utils/handle_generator.dart';

/// Shows a non-blocking "Signed in as &lt;handle&gt;" toast at the top
/// of the screen. Slides + fades in, dwells briefly, then dismisses
/// itself.
///
/// Implemented via [Overlay] so it floats above the home content
/// (including the ModeCards and AppBar slot) without depending on a
/// Scaffold's SnackBar slot — both keep the home layout untouched.
///
/// Idempotent within a session — calling this twice in quick
/// succession is fine; the second call queues a fresh entry on top
/// of (or after) the first.
void showSignedInToast(
  final BuildContext context, {
  required final String handle,
  required final String avatarId,
  final Duration dwell = const Duration(milliseconds: 1700),
}) {
  final OverlayState? overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (final BuildContext _) => _SignedInToast(
      handle: handle,
      avatarId: avatarId,
      dwell: dwell,
      onComplete: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _SignedInToast extends StatefulWidget {
  const _SignedInToast({
    required this.handle,
    required this.avatarId,
    required this.dwell,
    required this.onComplete,
  });

  final String handle;
  final String avatarId;
  final Duration dwell;
  final VoidCallback onComplete;

  @override
  State<_SignedInToast> createState() => _SignedInToastState();
}

class _SignedInToastState extends State<_SignedInToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const Duration _slideIn = Duration(milliseconds: 280);
  static const Duration _slideOut = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _slideIn)
      ..forward();
    // Schedule the dismiss animation after the dwell.
    Future<void>.delayed(_slideIn + widget.dwell, () async {
      if (!mounted) return;
      _ctrl.duration = _slideOut;
      await _ctrl.reverse();
      if (!mounted) return;
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final String emoji = HandleGenerator.emojiFor(widget.avatarId);
    return Positioned(
      // Sit just below the system safe area (notch / status bar).
      top: safe.top + 12,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        // Wrap in a transparent Material so the Text widgets inside
        // get a proper DefaultTextStyle ancestor — without this,
        // Overlay-hosted text renders with Flutter's yellow debug
        // double-underline (the "raw text in Overlay" footgun).
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: AnimatedBuilder(
            animation: _ctrl,
            builder: (final BuildContext context, final Widget? child) {
              final double t = Curves.easeOutCubic.transform(_ctrl.value);
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, -16 * (1 - t)),
                  child: child,
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xCC0F1E12),
                        Color(0xCC0A140A),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.goldBright.withValues(alpha: 0.7),
                      width: 1.4,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.goldBright.withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                      const BoxShadow(
                        color: Colors.black54,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Avatar bubble — small, dark with gold ring,
                      // matches the home top-bar profile button.
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            center: Alignment(-0.25, -0.35),
                            colors: <Color>[
                              Color(0xFF333333),
                              Color(0xFF111111),
                            ],
                          ),
                          border: Border.all(
                            color: AppColors.goldShine,
                            width: 1.4,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Two-line label — "Signed in as" / handle.
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Signed in as',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.handle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                    ],
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

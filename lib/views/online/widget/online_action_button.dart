import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/audio_helper.dart';

/// Single visual style for primary CTAs across the online flow:
/// FIND MATCH, CREATE ROOM, JOIN ROOM, JOIN!, etc.
///
/// Two visual variants via [primary]:
///   • `true`  — gold gradient on dark background (matches the home
///                screen's premium accent). Use for the main action on
///                each screen.
///   • `false` — outlined ghost button. Use for secondary actions
///                (CANCEL, BACK, REROLL).
///
/// The button auto-plays the standard select sound on tap (matches
/// every other tap-target in the app), so callers don't need to call
/// [AudioHelper.select] themselves. Set [playSound] to false to
/// suppress (useful in CANCEL flows that are about to play another
/// sound right after).
class OnlineActionButton extends StatelessWidget {
  const OnlineActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = true,
    this.compact = false,
    this.busy = false,
    this.playSound = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  final bool compact;

  /// When true, swaps the label/icon for a small spinner and disables
  /// the tap. Used by the action screens while a Firestore write is
  /// pending so the user can't double-fire.
  final bool busy;

  final bool playSound;

  bool get _enabled => onTap != null && !busy;

  @override
  Widget build(final BuildContext context) {
    final double vPad = compact ? 12 : 16;
    final double font = compact ? 14 : 17;
    final double iconSize = compact ? 18 : 22;

    final Widget child = busy
        ? SizedBox(
            height: iconSize,
            width: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: primary ? Colors.black : Colors.white,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: iconSize,
                  color: primary ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: AppFonts.bebasNeue(
                  fontSize: font,
                  letterSpacing: 2.2,
                  color: primary ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );

    return Opacity(
      opacity: _enabled ? 1.0 : 0.55,
      child: GestureDetector(
        onTap: _enabled
            ? () {
                if (playSound) AudioHelper.select();
                onTap?.call();
              }
            : null,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: vPad),
          decoration: BoxDecoration(
            gradient: primary
                ? const LinearGradient(
                    colors: <Color>[
                      AppColors.goldBright,
                      Color(0xFFFF9800),
                    ],
                  )
                : null,
            color: primary ? null : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: primary
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.3),
              width: primary ? 2 : 1,
            ),
            boxShadow: primary
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppColors.goldBright.withValues(alpha: 0.5),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

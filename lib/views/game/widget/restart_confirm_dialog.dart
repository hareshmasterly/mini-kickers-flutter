import 'package:flutter/material.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';

/// "Restart this match?" confirmation prompt.
///
/// Pop the dialog with `true` if the player confirms, `false` if they
/// cancel (KEEP PLAYING button, tap-outside, or Android back). Visually
/// matches the in-game exit dialog so the prompts feel like a family.
///
/// ```dart
/// final bool? confirmed = await showDialog<bool>(
///   context: context,
///   barrierColor: Colors.black87,
///   builder: (_) => const RestartConfirmDialog(),
/// );
/// if (confirmed != true) return;
/// // ... reset game
/// ```
class RestartConfirmDialog extends StatelessWidget {
  const RestartConfirmDialog({super.key});

  @override
  Widget build(final BuildContext context) {
    final bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final double maxWidth = isTablet ? 520 : 380;
    final EdgeInsets cardPad = isTablet
        ? const EdgeInsets.fromLTRB(36, 32, 36, 26)
        : const EdgeInsets.fromLTRB(24, 24, 24, 18);
    final double iconSize = isTablet ? 64 : 44;
    final double titleFont = isTablet ? 38 : 26;
    final double subtitleFont = isTablet ? 15 : 12;
    final double btnVPad = isTablet ? 16 : 12;
    final double cancelFont = isTablet ? 14 : 12;
    final double confirmFont = isTablet ? 15 : 13;
    final double gapAfterIcon = isTablet ? 12 : 8;
    final double gapAfterTitle = isTablet ? 8 : 5;
    final double gapBeforeButtons = isTablet ? 26 : 18;

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
              colors: <Color>[Color(0xFF101F10), Color(0xFF0A150A)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.brandYellow.withValues(alpha: 0.6),
              width: 2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.brandYellow.withValues(alpha: 0.35),
                blurRadius: 36,
                spreadRadius: 1,
              ),
              const BoxShadow(
                color: Colors.black87,
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.refresh_rounded,
                size: iconSize,
                color: AppColors.brandYellow,
              ),
              SizedBox(height: gapAfterIcon),
              Text(
                'RESTART MATCH?',
                style: AppFonts.bebasNeue(
                  fontSize: titleFont,
                  color: Colors.white,
                  letterSpacing: 1.4,
                ),
              ),
              SizedBox(height: gapAfterTitle),
              Text(
                'The current score and board will be reset.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: subtitleFont,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              SizedBox(height: gapBeforeButtons),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.85),
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
                          fontSize: cancelFont,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandYellow,
                        foregroundColor: Colors.black,
                        padding: EdgeInsets.symmetric(vertical: btnVPad),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'RESTART',
                        style: TextStyle(
                          fontSize: confirmFont,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
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

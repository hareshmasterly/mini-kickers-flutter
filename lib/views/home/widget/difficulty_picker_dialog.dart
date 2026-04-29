import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/ai_difficulty_option.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/audio_helper.dart';

/// Modal that pops when the user taps "VS AI" on the home screen. Lets
/// them pick (or change) the AI difficulty before the match starts.
///
/// Shown on **every** "VS AI" tap by design — that decision is locked
/// in §2 of [docs/vs_ai_feature_spec.md]. Two siblings on one device
/// often want different difficulties match-to-match, and the friction
/// of one extra tap is worth that flexibility.
///
/// Returns the picked [AiDifficulty] (or `null` if the user dismissed).
/// The caller is responsible for actually starting the AI match — this
/// dialog just collects the choice and persists it via
/// [SettingsService.setAiDifficulty].
Future<AiDifficulty?> showDifficultyPickerDialog(
  final BuildContext context,
) {
  return showDialog<AiDifficulty>(
    context: context,
    barrierColor: Colors.black87,
    builder: (final BuildContext _) => const _DifficultyPickerDialog(),
  );
}

class _DifficultyPickerDialog extends StatefulWidget {
  const _DifficultyPickerDialog();

  @override
  State<_DifficultyPickerDialog> createState() =>
      _DifficultyPickerDialogState();
}

class _DifficultyPickerDialogState extends State<_DifficultyPickerDialog> {
  late AiDifficulty _selected;

  @override
  void initState() {
    super.initState();
    _selected = SettingsService.instance.aiDifficulty;
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onCardTap(final AiDifficulty id) {
    AudioHelper.select();
    setState(() => _selected = id);
  }

  Future<void> _onStart() async {
    AudioHelper.select();
    await SettingsService.instance.setAiDifficulty(_selected);
    if (!mounted) return;
    Navigator.of(context).pop(_selected);
  }

  void _onCancel() {
    AudioHelper.select();
    Navigator.of(context).pop();
  }

  @override
  Widget build(final BuildContext context) {
    final List<AiDifficultyOption> options =
        SettingsService.instance.availableAiDifficulties;

    // Same three-tier breakpoint scheme as the rest of the app —
    // see [_CoinTossWidget._buildCard] for the canonical version.
    final Size screen = MediaQuery.of(context).size;
    final bool compact = screen.height < 400;
    final bool isTablet = !compact && screen.shortestSide >= 600;
    final double maxWidth = isTablet ? 600 : 480;
    final EdgeInsets cardPad = compact
        ? const EdgeInsets.fromLTRB(20, 18, 20, 16)
        : isTablet
            ? const EdgeInsets.fromLTRB(36, 30, 36, 26)
            : const EdgeInsets.fromLTRB(24, 24, 24, 22);
    final double titleFont = compact ? 22 : (isTablet ? 38 : 28);
    final double subtitleFont = compact ? 11 : (isTablet ? 14 : 12);
    final double gapAfterTitle = compact ? 12 : 16;
    final double gapBetweenCards = compact ? 8 : 10;
    final double gapBeforeButtons = compact ? 14 : 18;

    return Dialog(
      backgroundColor: Colors.transparent,
      // Don't add viewInsets — Dialog already adds them internally.
      // (Same lesson learned in TeamSetupStrip.)
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                  'CHOOSE DIFFICULTY',
                  textAlign: TextAlign.center,
                  style: AppFonts.bebasNeue(
                    fontSize: titleFont,
                    letterSpacing: 5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'How tough should the AI play?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: subtitleFont,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: gapAfterTitle),
                for (int i = 0; i < options.length; i++) ...<Widget>[
                  if (i > 0) SizedBox(height: gapBetweenCards),
                  _DifficultyCard(
                    option: options[i],
                    selected: _selected == options[i].id,
                    compact: compact,
                    isTablet: isTablet,
                    onTap: () => _onCardTap(options[i].id),
                  ),
                ],
                SizedBox(height: gapBeforeButtons),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _CancelButton(
                        compact: compact,
                        isTablet: isTablet,
                        onTap: _onCancel,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _StartButton(
                        compact: compact,
                        isTablet: isTablet,
                        onTap: _onStart,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.option,
    required this.selected,
    required this.compact,
    required this.isTablet,
    required this.onTap,
  });

  final AiDifficultyOption option;
  final bool selected;
  final bool compact;
  final bool isTablet;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final double padV = compact ? 10 : (isTablet ? 16 : 13);
    final double padH = compact ? 12 : (isTablet ? 18 : 14);
    final double emojiSize = compact ? 22 : (isTablet ? 32 : 26);
    final double nameFont = compact ? 14 : (isTablet ? 18 : 15);
    final double subtitleFont = compact ? 10 : (isTablet ? 13 : 11);
    final Color borderColor = selected
        ? AppColors.accent
        : Colors.white.withValues(alpha: 0.18);
    final Color bgColor = selected
        ? AppColors.accent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.05);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: <Widget>[
            if (option.emoji != null) ...<Widget>[
              Text(
                option.emoji!,
                style: TextStyle(fontSize: emojiSize),
              ),
              SizedBox(width: compact ? 10 : 14),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    option.name.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: nameFont,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  if (option.subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      option.subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: subtitleFont,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedScale(
              scale: selected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.check_circle_rounded,
                color: AppColors.accent,
                size: compact ? 20 : 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({
    required this.onTap,
    required this.compact,
    required this.isTablet,
  });

  final VoidCallback onTap;
  final bool compact;
  final bool isTablet;

  @override
  Widget build(final BuildContext context) {
    final double vPad = compact ? 11 : (isTablet ? 16 : 13);
    final double font = compact ? 12 : (isTablet ? 15 : 13);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        padding: EdgeInsets.symmetric(vertical: vPad),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      child: Text(
        'CANCEL',
        style: TextStyle(
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
          fontSize: font,
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.onTap,
    required this.compact,
    required this.isTablet,
  });

  final VoidCallback onTap;
  final bool compact;
  final bool isTablet;

  @override
  Widget build(final BuildContext context) {
    final double vPad = compact ? 11 : (isTablet ? 16 : 13);
    final double font = compact ? 16 : (isTablet ? 22 : 19);
    final double iconSize = compact ? 16 : (isTablet ? 22 : 20);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vPad),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[
              AppColors.goldBright,
              Color(0xFFFF9800),
            ],
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.play_arrow_rounded,
              size: iconSize,
              color: const Color(0xFF1B1B1B),
            ),
            const SizedBox(width: 6),
            Text(
              'START MATCH',
              style: AppFonts.bebasNeue(
                fontSize: font,
                letterSpacing: 3,
                color: const Color(0xFF1B1B1B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/theme/team_colors.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/views/settings/widget/palette_picker.dart';
import 'package:mini_kickers/views/settings/widget/player_name_tile.dart';

/// Pair of tappable team chips ("R · RED  vs  B · BLUE") that surfaces
/// the team-name / palette controls on the coin-toss card. Same controls
/// also live in Settings, but most users never look there — this puts
/// them in the natural pre-match moment.
///
/// Tapping either chip opens [showTeamSetupDialog], which reuses the
/// existing [PalettePicker] + [PlayerNameTile] widgets so the look and
/// the persistence behaviour are identical to Settings.
class TeamSetupStrip extends StatelessWidget {
  const TeamSetupStrip({super.key, this.compact = false, this.isTablet = false});

  final bool compact;
  final bool isTablet;

  @override
  Widget build(final BuildContext context) {
    // Listen so chip labels update live when the user edits names from
    // inside the dialog (or anywhere else).
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (final BuildContext context, final Widget? _) {
        final SettingsService s = SettingsService.instance;
        final double vsFont = compact ? 11 : (isTablet ? 16 : 13);
        final double gap = compact ? 6 : (isTablet ? 14 : 10);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: _TeamChip(
                team: Team.red,
                name: s.redName,
                isAi: false,
                compact: compact,
                isTablet: isTablet,
                onTap: () => showTeamSetupDialog(context),
              ),
            ),
            SizedBox(width: gap),
            Text(
              'VS',
              style: AppFonts.bebasNeue(
                fontSize: vsFont,
                letterSpacing: 2,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            SizedBox(width: gap),
            Flexible(
              child: _TeamChip(
                team: Team.blue,
                // `displayBlueName` returns the fixed "AI" label in
                // VS AI mode so the chip never shows a stale custom
                // name from a previous VS Human session.
                name: s.displayBlueName,
                // In VS AI mode the Blue chip represents the AI
                // opponent — show a small 🤖 marker so the user
                // knows which team is the bot.
                isAi: s.gameMode == GameMode.vsAi,
                compact: compact,
                isTablet: isTablet,
                onTap: () => showTeamSetupDialog(context),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TeamChip extends StatelessWidget {
  const _TeamChip({
    required this.team,
    required this.name,
    required this.isAi,
    required this.onTap,
    required this.compact,
    required this.isTablet,
  });

  final Team team;
  final String name;

  /// When true, prepends a 🤖 marker so the user knows this team is
  /// controlled by the AI in VS AI mode.
  final bool isAi;
  final VoidCallback onTap;
  final bool compact;
  final bool isTablet;

  @override
  Widget build(final BuildContext context) {
    final Color base = TeamColors.primary(team);
    final Color light = TeamColors.light(team);
    final double avatarSize = compact ? 22 : (isTablet ? 32 : 26);
    final double padV = compact ? 4 : (isTablet ? 8 : 6);
    final double padH = compact ? 9 : (isTablet ? 16 : 12);
    final double nameFont = compact ? 12 : (isTablet ? 16 : 13);
    final double editIcon = compact ? 12 : (isTablet ? 16 : 14);
    final double innerGap = compact ? 6 : (isTablet ? 10 : 8);

    return GestureDetector(
      onTap: () {
        AudioHelper.select();
        onTap();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: light.withValues(alpha: 0.65),
            width: 1.4,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: base.withValues(alpha: 0.32),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  colors: <Color>[
                    Color.lerp(base, Colors.white, 0.3)!,
                    base,
                  ],
                ),
                border: Border.all(color: light, width: 1.6),
              ),
              child: Center(
                child: Text(
                  _firstLetter(name),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: avatarSize * 0.55,
                    fontWeight: FontWeight.w900,
                    shadows: const <Shadow>[
                      Shadow(color: Colors.black45, blurRadius: 2),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: innerGap),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: nameFont,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (isAi) ...<Widget>[
                    SizedBox(width: compact ? 4 : 6),
                    Icon(
                      Icons.smart_toy_rounded,
                      size: editIcon + 1,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: compact ? 4 : 6),
            Icon(
              Icons.edit_rounded,
              size: editIcon,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the team-setup dialog. Lives at top-level so the coin-toss
/// strip and any future entry point (e.g. an "Edit Teams" button on
/// the home screen) can share the exact same UI.
Future<void> showTeamSetupDialog(final BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (final BuildContext _) => const _TeamSetupDialog(),
  );
}

class _TeamSetupDialog extends StatefulWidget {
  const _TeamSetupDialog();

  @override
  State<_TeamSetupDialog> createState() => _TeamSetupDialogState();
}

class _TeamSetupDialogState extends State<_TeamSetupDialog> {
  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(final BuildContext context) {
    final SettingsService s = SettingsService.instance;
    // Same three-tier breakpoint scheme used elsewhere in the app
    // (see [_CoinTossWidget._buildCard]).
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
    final double gapBetween = compact ? 8 : 10;
    final double gapBeforeDone = compact ? 14 : 18;

    // Don't add viewInsets to insetPadding — Flutter's Dialog widget
    // already does that internally (effectivePadding = insetPadding +
    // MediaQuery.viewInsets). Adding it here too made the available
    // area shrink by double the keyboard height, hiding the focused
    // text field behind the keyboard on iPad landscape.
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
                  'EDIT TEAMS',
                  textAlign: TextAlign.center,
                  style: AppFonts.bebasNeue(
                    fontSize: titleFont,
                    letterSpacing: 5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pick your colors and player names',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: subtitleFont,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: gapAfterTitle),
                PalettePicker(
                  currentId: s.palette.id,
                  onSelect: (final String id) => s.setPalette(id),
                ),
                SizedBox(height: gapBetween),
                PlayerNameTile(
                  team: Team.red,
                  initialName: s.redName,
                  onCommit: s.setRedName,
                ),
                SizedBox(height: gapBetween),
                // In VS AI mode, hide Blue's editable name tile — the
                // AI opponent is always shown as a single fixed label
                // ("AI"), not customisable. Replace with a read-only
                // info row so the dialog still has visual balance.
                // VS Human mode keeps both editors as before.
                if (s.gameMode == GameMode.vsAi)
                  const _AiOpponentRow()
                else
                  PlayerNameTile(
                    team: Team.blue,
                    initialName: s.blueName,
                    onCommit: s.setBlueName,
                  ),
                SizedBox(height: gapBeforeDone),
                _DoneButton(
                  compact: compact,
                  isTablet: isTablet,
                  onTap: () {
                    AudioHelper.select();
                    // Pop focus first so any in-flight TextField commit
                    // fires before the dialog closes.
                    FocusScope.of(context).unfocus();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.onTap,
    required this.compact,
    required this.isTablet,
  });

  final VoidCallback onTap;
  final bool compact;
  final bool isTablet;

  @override
  Widget build(final BuildContext context) {
    final double vPad = compact ? 12 : (isTablet ? 18 : 14);
    final double font = compact ? 18 : (isTablet ? 26 : 22);
    final double iconSize = compact ? 18 : (isTablet ? 26 : 22);
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
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.goldBright.withValues(alpha: 0.5),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.check_rounded,
              size: iconSize,
              color: const Color(0xFF1B1B1B),
            ),
            const SizedBox(width: 8),
            Text(
              'DONE',
              style: AppFonts.bebasNeue(
                fontSize: font,
                letterSpacing: 4,
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

String _firstLetter(final String s) {
  final String t = s.trim();
  return t.isEmpty ? '?' : t[0].toUpperCase();
}

/// Read-only row shown in place of Blue's [PlayerNameTile] when the
/// match is VS AI. Mirrors the visual language of [PlayerNameTile]
/// (avatar circle + label) so the dialog layout doesn't shift, but
/// has no text field — the AI's name is fixed.
class _AiOpponentRow extends StatelessWidget {
  const _AiOpponentRow();

  @override
  Widget build(final BuildContext context) {
    final Color base = TeamColors.primary(Team.blue);
    final Color light = TeamColors.light(Team.blue);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  colors: <Color>[
                    Color.lerp(base, Colors.white, 0.3)!,
                    base,
                  ],
                ),
                border: Border.all(color: light, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: base.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.smart_toy_rounded,
                  color: Colors.white,
                  size: 20,
                  shadows: <Shadow>[
                    Shadow(color: Colors.black54, blurRadius: 3),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    SettingsService.instance.displayBlueName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Playing against AI',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
